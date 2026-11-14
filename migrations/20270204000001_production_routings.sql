-- Work centres, routings and operations (ADR 0062): where and how a production order is built.
-- Work centres with their opening hours and closures, a routing (the operations) on a BOM
-- revision, and the operations a production order snapshots from it at release.

-- Order rows point at their production order with a composite key, so its (id, company_id) must
-- be unique.
ALTER TABLE production.production_orders
    ADD CONSTRAINT production_orders_id_company_key UNIQUE (id, company_id);

-- The standard cost of a component when the order was released: planned and actual cost of an
-- order must not move when a standard cost changes later.
ALTER TABLE production.order_components
    ADD COLUMN standard_cost numeric(18,4) CHECK (standard_cost >= 0);

-- A machine, bench or crew that operations run on.
CREATE TABLE production.work_centres (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES core.companies(id),
    code          text NOT NULL CHECK (btrim(code) <> ''),
    name          text NOT NULL CHECK (btrim(name) <> ''),
    division_id   uuid,
    -- parallel units (machines, crews) offered at once
    capacity      integer NOT NULL DEFAULT 1 CHECK (capacity BETWEEN 1 AND 1000),
    -- company currency; only shown to users with the cost permission
    cost_per_hour numeric(18,4) CHECK (cost_per_hour >= 0),
    active        boolean NOT NULL DEFAULT true,
    sort_order    integer NOT NULL DEFAULT 0,
    notes         text NOT NULL DEFAULT '',
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, code),
    UNIQUE (id, company_id),
    FOREIGN KEY (division_id, company_id) REFERENCES production.divisions (id, company_id)
);

-- Own opening hours; several blocks per weekday are allowed (a morning and an afternoon). A work
-- centre with no rows works the default week (Monday to Friday 08:00-12:00 and 13:00-17:00).
CREATE TABLE production.work_centre_hours (
    company_id     uuid NOT NULL,
    work_centre_id uuid NOT NULL,
    weekday        smallint NOT NULL CHECK (weekday BETWEEN 1 AND 7),
    start_time     time NOT NULL,
    end_time       time NOT NULL,
    PRIMARY KEY (work_centre_id, weekday, start_time),
    CHECK (end_time > start_time),
    FOREIGN KEY (work_centre_id, company_id) REFERENCES production.work_centres (id, company_id)
        ON DELETE CASCADE
);

-- Days nothing is worked: maintenance, holidays. No work centre means the whole plant is closed.
CREATE TABLE production.work_centre_closures (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES core.companies(id),
    work_centre_id uuid,
    from_date      date NOT NULL,
    to_date        date NOT NULL,
    kind           text NOT NULL DEFAULT 'other' CHECK (kind IN ('maintenance', 'holiday', 'other')),
    note           text NOT NULL DEFAULT '',
    created_by     uuid REFERENCES core.users(id),
    created_at     timestamptz NOT NULL DEFAULT now(),
    CHECK (to_date >= from_date),
    FOREIGN KEY (work_centre_id, company_id) REFERENCES production.work_centres (id, company_id)
        ON DELETE CASCADE
);
CREATE INDEX work_centre_closures_idx ON production.work_centre_closures (company_id, to_date);

-- The routing of a BOM revision: its operations in order. BOMs are shared master data without a
-- company, so each company keeps its own routing rows for a BOM. Editable while the BOM is a
-- draft (the BOM itself is frozen once it is active); a new revision copies them.
CREATE TABLE production.routing_operations (
    id                   uuid PRIMARY KEY,
    company_id           uuid NOT NULL REFERENCES core.companies(id),
    bom_id               uuid NOT NULL REFERENCES engineering.boms(id) ON DELETE CASCADE,
    position             integer NOT NULL CHECK (position > 0),
    name                 text NOT NULL CHECK (btrim(name) <> ''),
    work_centre_id       uuid NOT NULL,
    setup_minutes        integer NOT NULL DEFAULT 0 CHECK (setup_minutes >= 0),
    -- per unit of the product, in its stock unit
    run_minutes_per_unit numeric(12,4) NOT NULL DEFAULT 0 CHECK (run_minutes_per_unit >= 0),
    notes                text NOT NULL DEFAULT '',
    UNIQUE (company_id, bom_id, position),
    FOREIGN KEY (work_centre_id, company_id) REFERENCES production.work_centres (id, company_id)
);
CREATE INDEX routing_operations_work_centre_idx ON production.routing_operations (work_centre_id);

-- What a production order does: the routing as it was at release, with planned dates, and the
-- actual minutes recorded when an operation is finished.
CREATE TABLE production.order_operations (
    id                   uuid PRIMARY KEY,
    company_id           uuid NOT NULL REFERENCES core.companies(id),
    production_order_id  uuid NOT NULL,
    position             integer NOT NULL CHECK (position > 0),
    name                 text NOT NULL CHECK (btrim(name) <> ''),
    work_centre_id       uuid NOT NULL,
    setup_minutes        integer NOT NULL CHECK (setup_minutes >= 0),
    run_minutes_per_unit numeric(12,4) NOT NULL CHECK (run_minutes_per_unit >= 0),
    -- setup + run x order quantity, rounded up, at release
    planned_minutes      integer NOT NULL CHECK (planned_minutes >= 0),
    planned_start        date NOT NULL,
    planned_end          date NOT NULL,
    status               text NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'in_progress', 'done', 'skipped')),
    started_at           timestamptz,
    completed_at         timestamptz,
    completed_by         uuid REFERENCES core.users(id),
    -- total minutes worked, recorded when the operation is finished
    actual_minutes       integer CHECK (actual_minutes >= 0),
    -- the work centre's cost per hour when the order was released or the operation moved
    cost_rate            numeric(18,4) CHECK (cost_rate >= 0),
    notes                text NOT NULL DEFAULT '',
    UNIQUE (production_order_id, position),
    CHECK (planned_end >= planned_start),
    FOREIGN KEY (production_order_id, company_id) REFERENCES production.production_orders (id, company_id)
        ON DELETE CASCADE,
    FOREIGN KEY (work_centre_id, company_id) REFERENCES production.work_centres (id, company_id)
);
-- The load of a work centre: its open operations by date.
CREATE INDEX order_operations_load_idx ON production.order_operations (company_id, work_centre_id, planned_start)
    WHERE status IN ('pending', 'in_progress');
