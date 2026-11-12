# 0014 — Contacts, phone calls and the customer portal

**Status:** Accepted

**Context.** Until now a customer was one record with one e-mail address and one phone number, and
a ticket carried the sender as free text. Real customers are several people with different jobs
(sales contact, technician, purchasing, ...), who may speak another language than their company
and want to be addressed in a certain way. Staff also log phone calls and must find out who is
calling. Customers want to follow and raise tickets themselves.

**Decision.**
* **Contacts** (`crm.contacts`) belong to a customer and are shared across companies like
  customers. A person has *roles* (several), *several e-mail addresses* (each unique over all
  contacts, so mail can be matched) and *several phone numbers*. A contact is never deleted, only
  made inactive (tickets keep pointing at them); a former colleague's address still identifies
  them.
* **Language** is stored twice: `crm.customers.language` is the language of the company;
  `crm.contacts.language` is the person's own and may be empty ("same as the company"). The one to
  write in is `effective_language` = person, else customer, else (for unknown senders) detected
  text, else the company default.
* **How to address a person**: `title` (`mr` / `ms` / `none`) and `address_form` (`formal` /
  `informal`, i.e. u / vous / Sie / usted versus je / tu / du / tú). `contacts::greeting` builds the
  salutation per language; without a title the full name is used, so nobody is greeted with a
  guessed gender. It is available to prepared answers as `{{contact.salutation}}`. The address form
  does not change the *text* of a prepared answer (those exist per language only); the agent sees
  it and picks the wording.
* **Lookup.** E-mail: an incoming message is matched to a contact by exact address first (giving
  customer, person and language), then falls back to the earlier customer matching. Phone: numbers
  are stored as typed *and* normalised to digits with country code (`+32 (0)475/12.34.56`,
  `0032 475 ...` and, with the customer's country as default, `0475 ...` all become `32475...`).
  `GET /contacts/lookup` takes a phone number, e-mail address or name and also returns customers
  whose main number matches (a switchboard). A number shared by several people is never resolved
  automatically; the agent chooses.
* **Phone calls** are ticket articles (`call_in` / `call_out`) with number, duration and summary,
  logged with `POST /helpdesk/calls` on an existing ticket or a new one. An incoming call reopens a
  ticket that waited for the customer; calling back counts as a response. Nothing is sent.
* **Portal** (`crates/portal`, schema `portal`, Flutter entry point `lib/portal/portal_main.dart`).
  Login is **passwordless**: the contact asks for a link at their address, receives a single-use
  link valid 15 minutes (token in the URL fragment), and exchanges it for a 24-hour session. Only
  SHA-256 hashes of both tokens are stored. The request endpoint answers `202` for everyone (no
  customer enumeration) and sends at most one link a minute per person. Access is granted per
  contact (`portal_access`) and re-checked on every request, so switching it off, deactivating the
  person or the customer ends the session at once.
* **What a customer sees.** Their own tickets (`portal_scope = own`) or all tickets of their
  customer (`customer`); never internal tickets, internal notes, phone-call summaries or
  internal states (`new`, `open` and `pending_internal` all read "in progress"). They can open
  tickets (category question / service / complaint / other), reply (which reopens a closed
  ticket, like an e-mail reply) and set their own language, form of address and title.
* **System e-mail.** Login links are not tickets, so they go through `core.mail_outbox`, queued in
  the same transaction and sent by the worker with the same retry rules as the ticket outbox. The
  portal's address is `core.companies.portal_url` (one portal per company, because tickets are
  per company); without it no link is sent.
* **Audit.** Customer actions in the portal write `audit.events` without a user and with the
  contact in the data.

**Consequences.**
* `PUT /tickets/{id}` is a full update: clients must send `contact_id` back or the link is
  removed (the Flutter app does).
* A portal session token lives in the browser's local storage. It is revocable and short-lived,
  but readable by script on the portal's origin, so the portal must not host untrusted content.
* There is no rate limiting beyond the per-person link throttle; put the API behind a reverse
  proxy that limits requests per IP before exposing the portal.
  *Superseded by [ADR 0050](0050-portal-surface.md): customers reach a separate server with only
  the portal routes, which limits requests per client address; the API is not exposed at all.*
* The portal needs `portal_url` set on the company, SMTP configured for the worker, and the web
  server must serve `index.html` for unknown paths (`/login#token=...`).

**Later.** Orders, quotations and documents in the portal; attachments; self-service for
contact details; contact import from the CRM; SLA display; per-role portal permissions.
