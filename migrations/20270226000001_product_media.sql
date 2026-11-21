-- Pictures and videos of a product (ADR 0089). The bytes live in the file store (FILE_STORAGE_DIR) with a core.files metadata row like every other
-- upload; this table links them to a product, in display order. At most one is the default: the
-- one shown first (product page, lists, documents).
ALTER TABLE core.files DROP CONSTRAINT files_content_type_check;
ALTER TABLE core.files ADD CONSTRAINT files_content_type_check
    CHECK (content_type IN ('image/jpeg', 'image/png', 'image/webp', 'application/pdf',
                            'video/mp4', 'video/webm'));

CREATE TABLE products.media (
    file_id     uuid PRIMARY KEY REFERENCES core.files(id),
    company_id  uuid NOT NULL REFERENCES core.companies(id),
    product_id  uuid NOT NULL REFERENCES products.products(id) ON DELETE CASCADE,
    kind        text NOT NULL CHECK (kind IN ('image', 'video')),
    caption     text NOT NULL DEFAULT '',
    is_default  boolean NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX product_media_product_idx ON products.media (company_id, product_id, created_at);
CREATE UNIQUE INDEX product_media_one_default_idx ON products.media (product_id) WHERE is_default;
