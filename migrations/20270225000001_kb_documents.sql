CREATE TABLE kb.documents (
    id uuid PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES core.companies(id),
    title text NOT NULL CHECK (btrim(title) <> ''),
    kind text NOT NULL CHECK (kind IN ('technical_memo', 'product_presentation')),
    keywords text[] NOT NULL DEFAULT '{}',
    product_codes text[] NOT NULL DEFAULT '{}'
);
CREATE INDEX documents_company_idx ON kb.documents (company_id, title);

CREATE TABLE kb.document_revisions (
    document_id uuid NOT NULL REFERENCES kb.documents(id),
    revision integer NOT NULL CHECK (revision > 0),
    published_at timestamptz,
    PRIMARY KEY (document_id, revision)
);
CREATE UNIQUE INDEX document_one_draft ON kb.document_revisions (document_id)
    WHERE published_at IS NULL;

CREATE TABLE kb.document_pdfs (
    document_id uuid NOT NULL,
    revision integer NOT NULL,
    language text NOT NULL CHECK (language IN ('en', 'nl', 'fr', 'de', 'es')),
    file_id uuid NOT NULL REFERENCES core.files(id),
    PRIMARY KEY (document_id, revision, language),
    FOREIGN KEY (document_id, revision) REFERENCES kb.document_revisions(document_id, revision)
);
