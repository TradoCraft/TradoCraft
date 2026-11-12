-- Applied by `envctl clone` to every clone, always (ADR 0048). Runs inside one transaction, after
-- the clone was migrated to the schema of the current binary.
-- Clears everything that could let the clone act as, or log in as, someone in the live system, and
-- cancels mail that was still waiting to be sent. Mailbox (IMAP) and SMTP credentials are not in
-- the database at all: they are environment variables of the worker, which the outbound policy
-- overrides outside live.
BEGIN;

-- Customer portal: login links and sessions copied from live must not work in the clone.
DELETE FROM portal.login_links;
DELETE FROM portal.sessions;
-- Open satisfaction-survey links of live customers.
DELETE FROM helpdesk.csat_surveys;

-- Identity-provider bindings: the first OIDC sign-in binds again by e-mail address.
UPDATE core.users SET oidc_subject = NULL;

-- Mail that was still waiting to be sent in live must never be sent from the clone.
UPDATE core.mail_outbox
   SET delivery = 'failed', delivery_error = 'cancelled: environment clone'
 WHERE delivery = 'queued';
UPDATE helpdesk.articles
   SET delivery = 'failed', delivery_error = 'cancelled: environment clone'
 WHERE delivery = 'queued';

-- Login tokens in stored mail bodies (portal login links, survey links), whatever the delivery
-- state: the stored text must not contain a usable token.
UPDATE core.mail_outbox
   SET body = regexp_replace(body, 'token=[^[:space:]&"<>)]+', 'token=REDACTED', 'g')
 WHERE body ~ 'token=';
UPDATE helpdesk.articles
   SET body = regexp_replace(body, 'token=[^[:space:]&"<>)]+', 'token=REDACTED', 'g')
 WHERE body ~ 'token=';

-- The live worker's heartbeat says nothing about the clone; kept, the clone's first worker would
-- report the time since the dump as an outage (ADR 0052).
DELETE FROM core.worker_heartbeat;
DELETE FROM core.worker_outages;

COMMIT;
