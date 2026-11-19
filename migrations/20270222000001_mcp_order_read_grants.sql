-- A delegated order-read grant selects exactly one company for a subject and OAuth client.
CREATE TABLE core.mcp_order_read_grants (
    issuer      text NOT NULL,
    resource    text NOT NULL,
    subject     text NOT NULL,
    client_id   text NOT NULL,
    user_id     uuid NOT NULL,
    company_id  uuid NOT NULL,
    PRIMARY KEY (issuer, resource, subject, client_id),
    FOREIGN KEY (user_id, company_id) REFERENCES core.user_companies (user_id, company_id)
        ON DELETE CASCADE
);
