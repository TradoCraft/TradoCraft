-- Printable price lists (ADR 0074). A price list is a layout: which products, under which titled
-- groups, in which order. It stores no prices; they come from pricing.zone_prices of each zone the
-- list covers, valid on the list's valid_from, when the list is rendered.

-- Normalisation rules used below (ADR 0074):
--  * No arrays and no per-key jsonb for data that has its own identity or is looked up: titles,
--    descriptions, zone languages and export chapters are rows with keys and constraints.
--  * Every child table carries company_id and a composite foreign key (parent_id, company_id), so
--    a row can never belong to another company than its parent.
--  * Language codes are two lowercase letters like products.product_translations (ADR 0033);
--    zone languages are further limited to the languages of a company (nl, fr, en, de, es).

CREATE TABLE pricing.price_lists (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES core.companies(id),
    code           text NOT NULL CHECK (btrim(code) <> '' AND char_length(code) <= 32),
    name           text NOT NULL CHECK (btrim(name) <> ''),
    valid_from     date NOT NULL,
    -- Presentation only: footer_text, currency_symbol, accent_color, show_unit, show_logo. Always
    -- read and written as a whole, never filtered, joined or referenced by key, and none of it is
    -- an entity of its own, so one jsonb document is the right shape.
    settings       jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(settings) = 'object'),
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, code),
    -- Target of the (price_list_id, company_id) keys of the child tables.
    UNIQUE (id, company_id)
);

-- The price zones a list is published for.
CREATE TABLE pricing.price_list_zones (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES core.companies(id),
    price_list_id  uuid NOT NULL,
    price_zone_id  uuid NOT NULL REFERENCES pricing.price_zones(id),
    sort_order     integer NOT NULL DEFAULT 0,
    UNIQUE (price_list_id, price_zone_id),
    UNIQUE (id, company_id),
    FOREIGN KEY (price_list_id, company_id) REFERENCES pricing.price_lists (id, company_id) ON DELETE CASCADE
);
CREATE INDEX price_list_zones_zone_idx ON pricing.price_list_zones (price_zone_id);

-- The languages published for a zone; sort_order 0 is the default language.
CREATE TABLE pricing.price_list_zone_languages (
    price_list_zone_id uuid NOT NULL,
    company_id         uuid NOT NULL,
    language           char(2) NOT NULL CHECK (language IN ('nl', 'fr', 'en', 'de', 'es')),
    sort_order         integer NOT NULL CHECK (sort_order >= 0),
    PRIMARY KEY (price_list_zone_id, language),
    UNIQUE (price_list_zone_id, sort_order),
    FOREIGN KEY (price_list_zone_id, company_id)
        REFERENCES pricing.price_list_zones (id, company_id) ON DELETE CASCADE
);

-- A zone keeps at least one language. Checked at commit, so a zone and its languages can be
-- written in any order inside one transaction; deleting the zone itself (and with it the
-- languages) is fine.
CREATE FUNCTION pricing.check_price_list_zone_has_language() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    zone uuid;
BEGIN
    IF TG_TABLE_NAME = 'price_list_zones' THEN
        zone := NEW.id;
    ELSE
        zone := OLD.price_list_zone_id;
    END IF;
    IF EXISTS (SELECT 1 FROM pricing.price_list_zones WHERE id = zone)
       AND NOT EXISTS (SELECT 1 FROM pricing.price_list_zone_languages WHERE price_list_zone_id = zone)
    THEN
        RAISE EXCEPTION 'a price list zone needs at least one language' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER price_list_zones_need_language
    AFTER INSERT ON pricing.price_list_zones
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION pricing.check_price_list_zone_has_language();
CREATE CONSTRAINT TRIGGER price_list_zone_languages_keep_one
    AFTER DELETE OR UPDATE OF price_list_zone_id ON pricing.price_list_zone_languages
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION pricing.check_price_list_zone_has_language();

-- A tree of groups (chapter, group, sub-group). Depth is limited by the API.
CREATE TABLE pricing.price_list_groups (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES core.companies(id),
    price_list_id  uuid NOT NULL,
    parent_id      uuid,
    sort_order     integer NOT NULL DEFAULT 0,
    -- Start a new page before this group (honoured for top-level groups).
    page_break     boolean NOT NULL DEFAULT false,
    -- false: the title is kept for the editor but never printed; the group's items follow the
    -- previous group after a gap of gap_mm millimetres.
    show_title     boolean NOT NULL DEFAULT true,
    gap_mm         numeric(5,2) NOT NULL DEFAULT 0 CHECK (gap_mm BETWEEN 0 AND 50),
    -- Lets children, items and export links point at a group of the same list only.
    UNIQUE (price_list_id, id),
    UNIQUE (id, company_id),
    FOREIGN KEY (price_list_id, company_id) REFERENCES pricing.price_lists (id, company_id) ON DELETE CASCADE,
    FOREIGN KEY (price_list_id, parent_id) REFERENCES pricing.price_list_groups (price_list_id, id),
    CHECK (parent_id IS NULL OR parent_id <> id)
);
CREATE INDEX price_list_groups_list_idx ON pricing.price_list_groups (price_list_id, parent_id, sort_order);

-- The title of a group per language.
CREATE TABLE pricing.price_list_group_titles (
    group_id       uuid NOT NULL,
    company_id     uuid NOT NULL,
    language       char(2) NOT NULL CHECK (language ~ '^[a-z]{2}$'),
    title          text NOT NULL CHECK (btrim(title) <> '' AND char_length(title) <= 300),
    PRIMARY KEY (group_id, language),
    FOREIGN KEY (group_id, company_id) REFERENCES pricing.price_list_groups (id, company_id) ON DELETE CASCADE
);

CREATE TABLE pricing.price_list_items (
    id                 uuid PRIMARY KEY,
    company_id         uuid NOT NULL REFERENCES core.companies(id),
    price_list_id      uuid NOT NULL,
    product_id         uuid NOT NULL REFERENCES products.products(id),
    group_id           uuid NOT NULL,
    -- Dotted position inside the group, compared segment by segment ("1.2" before "1.10").
    sort_key           text NOT NULL DEFAULT '' CHECK (sort_key ~ '^[0-9A-Za-z]*(\.[0-9A-Za-z]+)*$'),
    price_on_request   boolean NOT NULL DEFAULT false,
    net                boolean NOT NULL DEFAULT false,
    indicative         boolean NOT NULL DEFAULT false,
    hidden             boolean NOT NULL DEFAULT false,
    UNIQUE (price_list_id, product_id),
    UNIQUE (id, company_id),
    FOREIGN KEY (price_list_id, company_id) REFERENCES pricing.price_lists (id, company_id) ON DELETE CASCADE,
    FOREIGN KEY (price_list_id, group_id) REFERENCES pricing.price_list_groups (price_list_id, id)
);
CREATE INDEX price_list_items_group_idx ON pricing.price_list_items (price_list_id, group_id);
CREATE INDEX price_list_items_product_idx ON pricing.price_list_items (product_id);

-- Text per language that replaces the product's own description in that language.
CREATE TABLE pricing.price_list_item_descriptions (
    item_id        uuid NOT NULL,
    company_id     uuid NOT NULL,
    language       char(2) NOT NULL CHECK (language ~ '^[a-z]{2}$'),
    description    text NOT NULL CHECK (btrim(description) <> '' AND char_length(description) <= 300),
    PRIMARY KEY (item_id, language),
    FOREIGN KEY (item_id, company_id) REFERENCES pricing.price_list_items (id, company_id) ON DELETE CASCADE
);

-- Export profiles: which chapters (top-level groups) go into one file. A profile without chapters
-- is the whole list; one chapter is an individual chapter, several are a combination.
CREATE TABLE pricing.price_list_exports (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES core.companies(id),
    price_list_id  uuid NOT NULL,
    code           text NOT NULL CHECK (btrim(code) <> '' AND char_length(code) <= 32),
    name           text NOT NULL CHECK (btrim(name) <> '' AND char_length(name) <= 120),
    sort_order     integer NOT NULL DEFAULT 0,
    -- Optional file name template; placeholders {list} {zone} {lang} {name} {code}. NULL means
    -- the profile name is used.
    file_name      text CHECK (file_name IS NULL OR (btrim(file_name) <> '' AND char_length(file_name) <= 120)),
    UNIQUE (price_list_id, code),
    UNIQUE (price_list_id, id),
    FOREIGN KEY (price_list_id, company_id) REFERENCES pricing.price_lists (id, company_id) ON DELETE CASCADE
);

-- The chapters of a profile, in the order of the profile. price_list_id sits in the link so that
-- both foreign keys are composite and the group provably belongs to the same list as the export.
-- The group side has no ON DELETE action (NO ACTION, checked at the end of the statement): a
-- group a profile uses cannot be deleted, while deleting the whole list, which removes the links
-- in the same statement, still works. (RESTRICT would fire before the cascade has removed them.)
CREATE TABLE pricing.price_list_export_groups (
    export_id      uuid NOT NULL,
    group_id       uuid NOT NULL,
    price_list_id  uuid NOT NULL,
    company_id     uuid NOT NULL,
    sort_order     integer NOT NULL CHECK (sort_order >= 0),
    PRIMARY KEY (export_id, group_id),
    UNIQUE (export_id, sort_order),
    FOREIGN KEY (price_list_id, export_id) REFERENCES pricing.price_list_exports (price_list_id, id) ON DELETE CASCADE,
    FOREIGN KEY (price_list_id, group_id) REFERENCES pricing.price_list_groups (price_list_id, id),
    FOREIGN KEY (price_list_id, company_id) REFERENCES pricing.price_lists (id, company_id) ON DELETE CASCADE
);
CREATE INDEX price_list_export_groups_group_idx ON pricing.price_list_export_groups (price_list_id, group_id);

-- Profiles select chapters only: a linked group must be top-level, and a linked group cannot be
-- moved below another group. (A foreign key cannot say "parent_id IS NULL".)
CREATE FUNCTION pricing.check_export_group_top_level() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pricing.price_list_groups WHERE id = NEW.group_id AND parent_id IS NOT NULL) THEN
        RAISE EXCEPTION 'an export profile can only select top-level groups' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER price_list_export_groups_top_level
    BEFORE INSERT OR UPDATE OF group_id ON pricing.price_list_export_groups
    FOR EACH ROW EXECUTE FUNCTION pricing.check_export_group_top_level();

CREATE FUNCTION pricing.check_used_group_stays_top_level() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pricing.price_list_export_groups WHERE group_id = NEW.id) THEN
        RAISE EXCEPTION 'a group used by an export profile must stay top-level' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER price_list_groups_used_stay_top_level
    BEFORE UPDATE OF parent_id ON pricing.price_list_groups
    FOR EACH ROW WHEN (NEW.parent_id IS NOT NULL)
    EXECUTE FUNCTION pricing.check_used_group_stays_top_level();
