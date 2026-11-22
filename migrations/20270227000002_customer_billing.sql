-- Customer sales documents are separate from the supplier invoice register.
CREATE TABLE finance.customer_documents (
    id                    uuid PRIMARY KEY,
    company_id            uuid NOT NULL REFERENCES core.companies(id),
    customer_id           uuid NOT NULL REFERENCES crm.customers(id),
    customer_name         text NOT NULL,
    kind                  text NOT NULL CHECK (kind IN ('invoice', 'credit_note')),
    status                text NOT NULL CHECK (status IN ('draft', 'posted')),
    number                text,
    document_date         date NOT NULL,
    due_date              date,
    currency              char(3) NOT NULL,
    language              text NOT NULL,
    vat_regime            text NOT NULL CHECK (vat_regime IN ('domestic', 'domestic_reverse_charge', 'intra_eu', 'outside_eu')),
    seller                jsonb NOT NULL,
    customer              jsonb NOT NULL,
    delivery_note_id      uuid REFERENCES delivery.delivery_notes(id),
    source_invoice_id     uuid REFERENCES finance.customer_documents(id),
    source_invoice_number text,
    reason                text NOT NULL DEFAULT '',
    is_legacy             boolean NOT NULL DEFAULT false,
    evidence_reference    text,
    request_id            uuid,
    request_payload       jsonb,
    net_total             numeric(18,2) NOT NULL DEFAULT 0 CHECK (net_total >= 0),
    vat_total             numeric(18,2) NOT NULL DEFAULT 0 CHECK (vat_total >= 0),
    gross_total           numeric(18,2) NOT NULL DEFAULT 0 CHECK (gross_total = net_total + vat_total),
    rebate_progress       jsonb,
    created_at            timestamptz NOT NULL DEFAULT now(),
    created_by            uuid NOT NULL REFERENCES core.users(id),
    posted_at             timestamptz,
    posted_by             uuid REFERENCES core.users(id),
    UNIQUE (company_id, request_id),
    UNIQUE (company_id, number),
    CHECK ((request_id IS NULL) = (request_payload IS NULL)),
    CHECK ((status = 'posted') = (number IS NOT NULL AND posted_at IS NOT NULL AND posted_by IS NOT NULL)),
    CHECK ((kind = 'credit_note') = (source_invoice_id IS NOT NULL AND source_invoice_number IS NOT NULL)),
    CHECK (kind <> 'credit_note' OR btrim(reason) <> ''),
    CHECK (delivery_note_id IS NOT NULL OR kind = 'credit_note' OR is_legacy),
    CHECK (NOT is_legacy OR (kind = 'invoice' AND status = 'posted' AND evidence_reference IS NOT NULL))
);

CREATE TABLE finance.customer_document_lines (
    id                     uuid PRIMARY KEY,
    document_id            uuid NOT NULL REFERENCES finance.customer_documents(id) ON DELETE CASCADE,
    position               integer NOT NULL,
    product_id             uuid REFERENCES products.products(id),
    product_code           text NOT NULL,
    description            text NOT NULL,
    unit                   text NOT NULL,
    quantity               numeric(22,8) NOT NULL CHECK (quantity > 0),
    stock_quantity         numeric(18,4),
    net_unit_price         numeric(18,4) NOT NULL CHECK (net_unit_price >= 0),
    net_total              numeric(18,2) NOT NULL CHECK (net_total >= 0),
    vat_rate               numeric(5,2) NOT NULL CHECK (vat_rate BETWEEN 0 AND 100),
    vat_total              numeric(18,2) NOT NULL CHECK (vat_total >= 0),
    gross_total            numeric(18,2) NOT NULL CHECK (gross_total = net_total + vat_total),
    included_in_turnover   boolean,
    delivery_line_id       uuid REFERENCES delivery.delivery_note_lines(id),
    source_invoice_line_id uuid REFERENCES finance.customer_document_lines(id),
    UNIQUE (document_id, position),
    UNIQUE (document_id, delivery_line_id),
    UNIQUE (document_id, source_invoice_line_id),
    CHECK ((delivery_line_id IS NULL) = (stock_quantity IS NULL)),
    CHECK (stock_quantity IS NULL OR stock_quantity > 0)
);

CREATE INDEX customer_documents_list_idx
    ON finance.customer_documents (company_id, document_date DESC, id DESC);
CREATE INDEX customer_documents_turnover_idx
    ON finance.customer_documents (company_id, customer_id, document_date)
    WHERE status = 'posted' AND NOT is_legacy;
CREATE INDEX customer_document_lines_delivery_idx
    ON finance.customer_document_lines (delivery_line_id) WHERE delivery_line_id IS NOT NULL;
CREATE INDEX customer_document_lines_credit_idx
    ON finance.customer_document_lines (source_invoice_line_id) WHERE source_invoice_line_id IS NOT NULL;
