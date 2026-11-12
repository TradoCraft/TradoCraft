# 0054 — Helpdesk mailboxes: several per company, Microsoft Graph or IMAP/SMTP

**Status:** Accepted

**Context.** The helpdesk had one mailbox, configured through worker environment variables
(`IMAP_*`, `SMTP_*`), for one company, and it signed in with a user name and a password. Exchange
Online refuses that sign-in (basic authentication is switched off for IMAP and is being retired
for SMTP), so a Microsoft 365 mailbox could not be used at all. Companies also want more than one
address (support, spare parts, a second brand), each with its own queue.

The ticket logic did not need to change. Two seams already existed: `ingest::ingest` takes the raw
bytes of an e-mail, and the mailer builds a complete MIME message.

**Decision.**

*Mailboxes.* `helpdesk.mailboxes` holds, per company: a name, the address, the kind (`graph` or
`imap_smtp`), the team new tickets start in, whether it fetches mail, whether it is the default,
and the settings of its kind. One mailbox per company can be the default (a partial unique
index); it carries system mail (portal login links, SLA notices) and replies on tickets that have
no mailbox. `helpdesk.tickets.mailbox_id` remembers where a ticket came in and
`helpdesk.articles.mailbox_id` where a message was received or sent. Administration is
`GET/POST /helpdesk/mailboxes` and `PUT/DELETE /helpdesk/mailboxes/{id}` behind `helpdesk.admin`,
audited, with a section in the helpdesk settings of the app.

*Secrets stay out of the database.* A mailbox has a `secret_ref` (upper-case letters, digits,
underscores). The worker reads the password or client secret from its environment variable
`MAILBOX_SECRET_<secret_ref>`. The API cannot store, return or test a secret. This keeps the
guarantee of ADR 0048 (a clone cannot carry mail credentials) and keeps secrets out of backups
(ADR 0056). The price: adding a mailbox needs someone with access to the server, once.

*Microsoft Graph (Exchange Online).* The worker signs in as an application (client credentials,
scope `https://graph.microsoft.com/.default`); the token is cached per tenant and application
until two minutes before it expires, and forgotten when Graph answers 401.
- Fetching: list the unread messages of the inbox, download each as raw MIME
  (`/messages/{id}/$value`), ingest it, then mark it read. As with IMAP, a message is marked read
  only after it is stored, and one that cannot be ingested stays unread. At most 200 per pass.
- Sending: the MIME message is uploaded as a draft (`POST /users/{mailbox}/messages`, base64),
  then sent (`/send`). The draft's answer carries the Message-ID Exchange assigned, which replaces
  ours on the article, so a customer's reply threads onto the ticket even when Exchange rewrote
  the header. If sending fails, the draft is deleted. The ticket number in the subject remains
  the second way to find the ticket.
- Not used: EWS (being retired), change notifications (they need a public webhook, and the staff
  API is deliberately not published, ADR 0050; the worker polls as before), and Graph's
  `reply`/`replyAll` (the helpdesk composes its own messages and tracks delivery).

*IMAP/SMTP.* The existing code, now per mailbox: Exchange Server on-premises and any other server
that still accepts a password.

*Routing.* A new ticket gets the mailbox and the mailbox's team (else the default team). A reply
is sent from the ticket's mailbox when it is still active, else from the default mailbox, else
(no mailboxes) from the company address through the worker's own transport, as before. The
outbox picks the transport per e-mail. When the mailbox of an e-mail cannot send (its secret is
missing, or it was switched off after the reply was queued), the e-mail fails with that reason;
it never leaves through another server. Failed e-mails go behind the others in the queue, so one
broken mailbox does not hold up the rest.

*Worker.* On every pass it reads the active mailboxes (a change in the app needs no restart),
fetches each, and writes `last_poll_at`, `last_ok_at` and `last_error` (the whole error chain, at
most 500 characters, never a secret or token), which the app shows. One failing mailbox does not
stop the others.

*Outbound safety (ADR 0048).* Outside a live environment mailboxes are never used for sending:
everything goes to files. Fetching follows the existing opt-in. In addition `envctl clone`
switches every mailbox off in the clone, so a clone whose worker happens to have the secrets
still touches no real mailbox.

*Compatibility.* The `IMAP_*`, `SMTP_*` and `MAIL_TRANSPORT` variables keep working: a company
without mailboxes behaves exactly as before.

**Consequences.**

* A Microsoft 365 administrator must register an application with the `Mail.ReadWrite` and
  `Mail.Send` application permissions and should restrict it to the helpdesk mailboxes; the
  runbook [helpdesk-mailboxes.md](../runbooks/helpdesk-mailboxes.md) describes it. Without that
  restriction the application could read every mailbox of the tenant.
* The Graph client is tested against a local stand-in (sign-in, paging, MIME download,
  mark-read-after-store, draft-then-send, failure and throttling answers). It has not run against
  a real tenant here; the runbook ends with the checks to do once on a test mailbox.
* The same message delivered to two helpdesk mailboxes becomes one ticket: Message-IDs are unique
  across the helpdesk. That also stops a reply sent from one mailbox with another in copy from
  coming back as a new message.
* Mail is fetched by polling, so a new e-mail appears after at most one worker pass
  (`POLL_SECONDS`), not instantly. Graph throttling (HTTP 429) shows as the mailbox's error and the
  next pass tries again; there is no back-off beyond the polling interval.
* The app does not yet show on a ticket which mailbox it belongs to, and a ticket cannot be moved
  to another mailbox. Both are small follow-ups.
* A Graph mailbox reads the inbox only; an IMAP mailbox reads the folder it names.
