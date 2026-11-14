-- Applied by `envctl clone --anonymize` after scrub_credentials.sql (ADR 0048). One transaction.
-- Replaces e-mail addresses and phone numbers of customers, suppliers, contacts, tickets and
-- queued mail, and drops stored raw e-mails and mail attachments. Ids, codes, names, amounts and
-- links between records are kept so the data still behaves like the original. Users keep their
-- e-mail address when they hold the admin role in some company (so sign-in still works); all other
-- users are replaced.
-- Not scrubbed: company, customer and product names, street addresses, VAT numbers, IBANs,
-- free-text notes, ticket subjects and bodies, audit data. A privacy aid, not a guarantee.
BEGIN;

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
       raw_message = NULL,
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
           AND k.conrelid <> 'core.file_blobs'::regclass
    LOOP
        EXECUTE format('DELETE FROM gone_files WHERE file_id IN (SELECT %I FROM %s)', r.col, r.tbl);
    END LOOP;
    DELETE FROM core.files WHERE id IN (SELECT file_id FROM gone_files);
END $$;

-- System mail still in the table: addresses and the attached document.
UPDATE core.mail_outbox
   SET to_address = 'recipient-' || left(md5(id::text), 10) || '@example.test',
       attachment_name = NULL, attachment_type = NULL, attachment_data = NULL;

COMMIT;
