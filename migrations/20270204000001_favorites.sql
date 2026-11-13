-- Sales favorites (ADR 0062): a main product with its option lines and comments, stored once for
-- the whole company and loaded into a quotation. A favorite stores no prices.

CREATE TABLE sales.favorites (
    id         uuid PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES core.companies(id),
    name       text NOT NULL CHECK (btrim(name) <> '' AND char_length(name) <= 120),
    created_by uuid NOT NULL REFERENCES core.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
-- Names are unique per company, ignoring case.
CREATE UNIQUE INDEX favorites_company_name_key ON sales.favorites (company_id, lower(name));

CREATE TABLE sales.favorite_items (
    id                uuid PRIMARY KEY,
    favorite_id       uuid NOT NULL REFERENCES sales.favorites(id) ON DELETE CASCADE,
    position          integer NOT NULL CHECK (position >= 1),
    -- The position of the parent item (an earlier one); NULL for the single main item.
    parent_position   integer,
    product_id        uuid NOT NULL REFERENCES products.products(id),
    -- Main item: the default quantity. Other items: the quantity per ONE unit of the main item.
    quantity          numeric(18,4) NOT NULL CHECK (quantity > 0),
    section           text,
    -- The small printed comment under the line (single text, no language).
    comment           text,
    -- Internal production remark (single text, no language).
    production_remark text NOT NULL DEFAULT '',
    percent_of_parent numeric(7,3),
    percent_base      text CHECK (percent_base IN ('parent_list_unit_price', 'parent_net_unit_price')),
    -- Deferred so that an edit can renumber the items inside one transaction.
    CONSTRAINT favorite_items_position_key UNIQUE (favorite_id, position) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT favorite_items_parent_earlier CHECK (parent_position IS NULL OR parent_position < position),
    CONSTRAINT favorite_items_percent_complete CHECK ((percent_of_parent IS NULL) = (percent_base IS NULL)),
    CONSTRAINT favorite_items_percent_needs_parent CHECK (percent_of_parent IS NULL OR parent_position IS NOT NULL)
);
-- Exactly one main item per favorite (at most one here; "at least one" is checked by the API).
CREATE UNIQUE INDEX favorite_items_one_main ON sales.favorite_items (favorite_id) WHERE parent_position IS NULL;
CREATE INDEX favorite_items_product_idx ON sales.favorite_items (product_id);

-- The customer-facing remark of an item, one text per language.
CREATE TABLE sales.favorite_item_remarks (
    item_id  uuid NOT NULL REFERENCES sales.favorite_items(id) ON DELETE CASCADE,
    language char(2) NOT NULL CHECK (language IN ('nl', 'fr', 'en', 'de', 'es')),
    text     text NOT NULL CHECK (btrim(text) <> '' AND char_length(text) <= 2000),
    PRIMARY KEY (item_id, language)
);

-- Quotation lines remember which language their customer remark is written in and which favorite
-- item they were loaded from (so a translation can be added to the favorite later).
ALTER TABLE sales.quotation_lines
    ADD COLUMN customer_remark_language char(2) CHECK (customer_remark_language IN ('nl', 'fr', 'en', 'de', 'es')),
    ADD COLUMN favorite_item_id uuid REFERENCES sales.favorite_items(id) ON DELETE SET NULL;
CREATE INDEX quotation_lines_favorite_item_idx ON sales.quotation_lines (favorite_item_id)
    WHERE favorite_item_id IS NOT NULL;
