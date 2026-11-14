-- Finance: supplier invoices (accounts payable register) and the three-way match (ADR 0046).

CREATE SCHEMA IF NOT EXISTS finance;

-- Per-company match tolerances, in percent.
CREATE TABLE finance.settings (
    company_id             uuid PRIMARY KEY REFERENCES core.companies(id) ON DELETE CASCADE,
    quantity_tolerance_pct numeric(7, 4) NOT NULL DEFAULT 0 CHECK (quantity_tolerance_pct >= 0),
    price_tolerance_pct    numeric(7, 4) NOT NULL DEFAULT 2 CHECK (price_tolerance_pct >= 0),
    updated_by_user_id     uuid REFERENCES core.users(id),
    updated_at             timestamptz NOT NULL DEFAULT now()
);

-- Supplier invoices as received, registered for matching, approval and payment tracking.
CREATE TABLE finance.supplier_invoices (
    id                  uuid PRIMARY KEY,
    company_id          uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
    number              text NOT NULL,
    supplier_id         uuid NOT NULL REFERENCES purchasing.suppliers(id) ON DELETE RESTRICT,
    purchase_order_id   uuid REFERENCES purchasing.purchase_orders(id) ON DELETE RESTRICT,
    invoice_number      text NOT NULL,
    invoice_date        date NOT NULL,
    due_date            date NOT NULL,
    currency            text NOT NULL,
    status              text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'matched', 'disputed', 'approved', 'paid')),
    net_total           numeric(15, 2) NOT NULL DEFAULT 0,
    vat_total           numeric(15, 2) NOT NULL DEFAULT 0,
    gross_total         numeric(15, 2) NOT NULL DEFAULT 0,
    notes               text NOT NULL DEFAULT '',
    dispute_reason      text NOT NULL DEFAULT '',
    override_reason     text NOT NULL DEFAULT '',
    created_by_user_id  uuid NOT NULL REFERENCES core.users(id),
    approved_by_user_id uuid REFERENCES core.users(id),
    approved_at         timestamptz,
    paid_at             date,
    payment_reference   text NOT NULL DEFAULT '',
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, number),
    UNIQUE (company_id, supplier_id, invoice_number)
);

CREATE INDEX supplier_invoices_status_idx ON finance.supplier_invoices (company_id, status);
CREATE INDEX supplier_invoices_po_idx ON finance.supplier_invoices (company_id, purchase_order_id);

-- Invoice lines; a line that points at a purchase order line takes part in the match.
CREATE TABLE finance.supplier_invoice_lines (
    id                     uuid PRIMARY KEY,
    invoice_id             uuid NOT NULL REFERENCES finance.supplier_invoices(id) ON DELETE CASCADE,
    line_number            integer NOT NULL,
    purchase_order_line_id uuid REFERENCES purchasing.purchase_order_lines(id) ON DELETE RESTRICT,
    product_id             uuid REFERENCES products.products(id) ON DELETE RESTRICT,
    description            text NOT NULL DEFAULT '',
    quantity               numeric(15, 4) NOT NULL CHECK (quantity > 0),
    unit_price             numeric(15, 4) NOT NULL CHECK (unit_price >= 0),
    vat_rate               numeric(5, 2) NOT NULL DEFAULT 0 CHECK (vat_rate >= 0 AND vat_rate <= 100),
    line_net               numeric(15, 2) NOT NULL,
    line_vat               numeric(15, 2) NOT NULL,
    line_gross             numeric(15, 2) NOT NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    UNIQUE (invoice_id, line_number)
);

CREATE INDEX supplier_invoice_lines_po_line_idx ON finance.supplier_invoice_lines (purchase_order_line_id);

-- Finance needs purchasing (ADR 0028, 0046): where purchasing is off, finance is off too.
UPDATE core.companies
SET disabled_modules = array_append(disabled_modules, 'finance')
WHERE 'purchasing' = ANY (disabled_modules)
  AND NOT ('finance' = ANY (disabled_modules));

UPDATE core.user_companies
SET disabled_modules = array_append(disabled_modules, 'finance')
WHERE 'purchasing' = ANY (disabled_modules)
  AND NOT ('finance' = ANY (disabled_modules));
