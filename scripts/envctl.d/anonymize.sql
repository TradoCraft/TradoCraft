-- Applied by `envctl clone --anonymize` after scrub_credentials.sql (ADR 0048). One transaction.
-- Replaces e-mail addresses and phone numbers of customers, suppliers, contacts, tickets, mailing
-- opt-outs (mapped to the replaced customer and contact addresses) and queued mail, clears
-- unsubscribe token hashes, and drops stored raw e-mails and mail attachments. Ids, codes, names,
-- amounts and links between records are kept so the data still behaves like the original. Users
-- keep their e-mail address when they hold the admin role in some company (so sign-in still
-- works); all other users are replaced.
-- Not scrubbed: company, customer and product names, street addresses, VAT numbers, IBANs,
-- free-text notes, ticket subjects and bodies, audit data. A privacy aid, not a guarantee.
BEGIN;

-- Mailing opt-outs (ADR 0099) are keyed by address. Before customer and contact addresses are
-- replaced, record which replacement address(es) each original address gets (the same
-- expressions as the updates below), so an opted-out person stays opted out after anonymizing.
-- Customers and contacts can share an address: one original can map to several replacements.
CREATE TEMP TABLE opt_out_addresses ON COMMIT DROP AS
SELECT lower(btrim(email)) AS original,
       'customer-' || left(md5(id::text), 10) || '@example.test' AS replacement
  FROM crm.customers
 WHERE lower(btrim(email)) IN (SELECT email FROM crm.mailing_opt_outs)
UNION
SELECT lower(btrim(email)),
       'contact-' || left(md5(contact_id::text), 10) || '-' || left(md5(id::text), 10) || '@example.test'
  FROM crm.contact_emails
 WHERE lower(btrim(email)) IN (SELECT email FROM crm.mailing_opt_outs);

UPDATE crm.customers
   SET email = 'customer-' || left(md5(id::text), 10) || '@example.test',
       phone = CASE WHEN phone IS NULL OR phone = '' THEN phone ELSE '+32 000 00 00 00' END;

UPDATE purchasing.suppliers
   SET email = 'supplier-' || left(md5(id::text), 10) || '@example.test',
       phone = CASE WHEN phone = '' THEN '' ELSE '+32 000 00 00 00' END,
       contact_person = CASE WHEN contact_person = '' THEN '' ELSE 'Contact' END;

UPDATE core.companies
   SET email = 'company-' || left(md5(id::text), 10) || '@example.test',
       phone = CASE WHEN phone IS NULL OR phone = '' THEN phone ELSE '+32 000 00 00 00' END;

-- Contact addresses are unique and lower case.
UPDATE crm.contact_emails
   SET email = 'contact-' || left(md5(contact_id::text), 10) || '-' || left(md5(id::text), 10)
               || '@example.test';

-- Contact phone numbers: a synthetic international number per row ("+32 470 000001"), unique in
-- the table. `normalized` is the same number as crm normalises it (digits with country code, here
-- 32470000001), which is what find_by_phone looks up.
UPDATE crm.contact_phones p
   SET number = '+32 470 ' || lpad(r.rn::text, 6, '0'),
       normalized = '32470' || lpad(r.rn::text, 6, '0')
  FROM (SELECT id, row_number() OVER (ORDER BY id) AS rn FROM crm.contact_phones) r
 WHERE r.id = p.id;

-- Users other than admins (the unique lower-case index stays satisfied: ids differ).
UPDATE core.users u
   SET email = 'user-' || left(md5(u.id::text), 10) || '@example.test',
       display_name = 'User ' || left(md5(u.id::text), 4)
 WHERE NOT EXISTS (SELECT 1 FROM core.user_companies uc
                    WHERE uc.user_id = u.id AND 'admin' = ANY (uc.roles));

-- Helpdesk: addresses and raw messages.
UPDATE helpdesk.tickets
   SET contact_email = CASE WHEN contact_email = '' THEN ''
                            ELSE 'ticket-' || left(md5(id::text), 10) || '@example.test' END,
       contact_name = CASE WHEN contact_name = '' THEN '' ELSE 'Contact' END;
UPDATE helpdesk.articles
   SET from_address = CASE WHEN from_address = '' THEN ''
                           ELSE 'sender-' || left(md5(id::text), 10) || '@example.test' END,
       from_name = CASE WHEN from_name = '' THEN '' ELSE 'Sender' END,
       to_addresses = ARRAY(SELECT 'recipient-' || left(md5(id::text), 10) || '-' || n || '@example.test'
                              FROM generate_series(1, COALESCE(array_length(to_addresses, 1), 0)) n),
       cc_addresses = ARRAY(SELECT 'cc-' || left(md5(id::text), 10) || '-' || n || '@example.test'
                              FROM generate_series(1, COALESCE(array_length(cc_addresses, 1), 0)) n),
       raw_message_storage_key = NULL,
       phone_number = NULL;

-- Ticket attachments (links, metadata and blobs). A file is only deleted when nothing else
-- (knowledge base, field service, repairs, packages) references it.
DO $$
DECLARE
    r record;
BEGIN
    CREATE TEMP TABLE gone_files ON COMMIT DROP AS SELECT file_id FROM helpdesk.ticket_attachments;
    DELETE FROM helpdesk.ticket_attachments;
    FOR r IN
        SELECT k.conrelid::regclass::text AS tbl, a.attname AS col
          FROM pg_constraint k
          JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
         WHERE k.contype = 'f' AND k.confrelid = 'core.files'::regclass
    LOOP
        EXECUTE format('DELETE FROM gone_files WHERE file_id IN (SELECT %I FROM %s)', r.col, r.tbl);
    END LOOP;
    DELETE FROM core.files WHERE id IN (SELECT file_id FROM gone_files);
END $$;

-- System mail still in the table: addresses and the attached document.
-- Rebuild mailing previews from the anonymized contacts before they can be confirmed.
UPDATE crm.mail_merge_drafts SET approved_preview = NULL;
-- Mailing opt-outs (ADR 0099): the register is rewritten with the replacement addresses mapped
-- above, so no original address is kept. An opt-out that matches no customer or contact gets a
-- hashed placeholder. When several originals end up at one address, the earliest opt-out is kept.
CREATE TEMP TABLE opt_outs_anonymized ON COMMIT DROP AS
SELECT DISTINCT ON (o.company_id, a.email)
       o.company_id, a.email, o.opted_out_at, o.source, o.recorded_by
  FROM crm.mailing_opt_outs o
  CROSS JOIN LATERAL (
      SELECT m.replacement AS email FROM opt_out_addresses m WHERE m.original = o.email
      UNION ALL
      SELECT 'opt-out-' || left(md5(o.email), 16) || '@example.test'
       WHERE NOT EXISTS (SELECT 1 FROM opt_out_addresses m WHERE m.original = o.email)
  ) a
 ORDER BY o.company_id, a.email, o.opted_out_at;
DELETE FROM crm.mailing_opt_outs;
INSERT INTO crm.mailing_opt_outs (company_id, email, opted_out_at, source, recorded_by)
SELECT company_id, email, opted_out_at, source, recorded_by FROM opt_outs_anonymized;
-- The unsubscribe links in the real mailboxes must not work against the clone.
UPDATE crm.mailing_deliveries SET unsubscribe_token_hash = NULL
 WHERE unsubscribe_token_hash IS NOT NULL;
UPDATE core.mail_outbox o
   SET subject = 'Anonymized mailing', body = 'Anonymized mailing', delivery_error = NULL
  FROM crm.mailing_deliveries d
 WHERE o.id = d.outbox_id;
UPDATE core.mail_outbox
   SET to_address = 'recipient-' || left(md5(id::text), 10) || '@example.test',
       attachment_name = NULL, attachment_type = NULL, attachment_storage_key = NULL;

COMMIT;
