-- Material requirements planning (ADR 0091, C2): planning parameters on products and the proposals
-- a run makes. A run replaces the open proposals of the company; nothing is bought or built until a
-- planner converts a proposal.

ALTER TABLE products.products
    -- Stock that should always be on hand; planning orders to keep the projection at or above it
    -- (the larger of this and `reorder_min` counts).
    ADD COLUMN safety_stock   numeric(18,4) CHECK (safety_stock >= 0),
    -- Orders are rounded up to a multiple of this (a pack, a pallet, a batch).
    ADD COLUMN order_multiple numeric(18,4) CHECK (order_multiple > 0);

CREATE SCHEMA IF NOT EXISTS mrp;

CREATE TABLE mrp.runs (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES core.companies(id),
    number        text NOT NULL,
    -- the day the plan starts from: what is due before it counts as due today
    planned_on    date NOT NULL,
    horizon_days  integer NOT NULL CHECK (horizon_days BETWEEN 1 AND 730),
    run_by        uuid REFERENCES core.users(id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    -- how many proposals the run made
    proposals     integer NOT NULL DEFAULT 0 CHECK (proposals >= 0),
    UNIQUE (company_id, number)
);

CREATE TABLE mrp.proposals (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES core.companies(id),
    run_id        uuid NOT NULL REFERENCES mrp.runs(id) ON DELETE CASCADE,
    product_id    uuid NOT NULL REFERENCES products.products(id),
    -- purchase: a purchase order for a bought product; production: a production order for a built one
    kind          text NOT NULL CHECK (kind IN ('purchase', 'production')),
    quantity      numeric(18,4) NOT NULL CHECK (quantity > 0),
    -- when the stock is needed, and when the order has to be placed (or the build started) for it
    need_date     date NOT NULL,
    order_date    date NOT NULL,
    -- the order date had to be today: the lead time reaches past the need date
    late          boolean NOT NULL DEFAULT false,
    supplier_id   uuid REFERENCES purchasing.suppliers(id),
    -- demand: a requirement is not covered; safety_stock: only the safety stock or reorder level is
    reason        text NOT NULL CHECK (reason IN ('demand', 'safety_stock')),
    -- what the quantity is for: [{kind, id, number, quantity}]
    pegging       jsonb NOT NULL DEFAULT '[]'::jsonb,
    status        text NOT NULL DEFAULT 'open'
                  CHECK (status IN ('open', 'converted', 'dismissed', 'superseded')),
    -- the purchase order or production order made from it
    converted_to  uuid,
    converted_at  timestamptz,
    converted_by  uuid REFERENCES core.users(id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    CHECK ((status = 'converted') = (converted_to IS NOT NULL)),
    CHECK (kind = 'purchase' OR supplier_id IS NULL)
);
CREATE INDEX mrp_proposals_company_status_idx ON mrp.proposals (company_id, status, need_date);
CREATE INDEX mrp_proposals_run_idx ON mrp.proposals (run_id);
CREATE INDEX mrp_proposals_product_idx ON mrp.proposals (company_id, product_id);
