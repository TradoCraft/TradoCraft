# 0099 — Mail merge opt-out and unsubscribe link

**Status:** Accepted (builds on [ADR 0098](0098-document-library-and-mail-merge.md),
[ADR 0050](0050-portal-surface.md) and the satisfaction survey links of
[ADR 0017](0017-helpdesk-sla-teams-attachments.md))

**Context.** The customer mail merge of [ADR 0098](0098-document-library-and-mail-merge.md) sends a
library PDF to every active customer that has commercial terms with the company. It did not ask
whether a recipient still wanted these mailings and gave recipients no way to stop them. The
recipients are existing business customers, and the mailings are about the company's own products
and services, so the owner chose an opt-out model (the EU "soft opt-in" for existing customers):
customers are mailed until they object, and every mailing must let them object with one click.

**Decision.** In the knowledge-base crate (`tradocraft-kb`, modules `mail_merge` and
`unsubscribe`); migration `20270306000001_mailing_opt_outs.sql`.

1. **An opt-out register per company, keyed by address.** `crm.mailing_opt_outs` (`company_id`,
   `email`, `opted_out_at`, `source`, `recorded_by`), primary key (`company_id`, `email`).
   Customers are shared master data, but each company sends on its own behalf, so an opt-out for
   one company does not stop mailings from another. The address is stored trimmed and lowercased
   (a check constraint enforces it), the same normalisation the mail merge applies to recipients.
   `source` is `staff` (recorded by a user, `recorded_by` set) or `unsubscribe_link`.
2. **The preview leaves opted-out addresses out.** After a recipient's address is resolved and
   normalised, the row gets the problem `opted_out` when the address is on the company's register.
   Rows with problems are not sent, and confirming already rebuilds the preview and refuses (409)
   when the eligible recipients differ from the approved ones, so an opt-out recorded between
   review and confirmation stops the mailing until it is reviewed again.
3. **An unsubscribe link in every mail.** Confirming needs a non-empty `core.companies.portal_url`
   and is otherwise refused (422) with a message to set the portal address. Each delivery gets a
   random 256-bit token (prefix `tcu_`) of which only the SHA-256 hash is stored, in
   `crm.mailing_deliveries.unsubscribe_token_hash` (unique; empty for deliveries queued before this
   change). The body gets a footer in the recipient's language (`en`, `nl`, `fr`, `de`, `es`)
   naming the company, with the link `{portal_url}/unsubscribe#token=<token>`. Links do not
   expire: a recipient may object at any time. The preview shows each recipient the same footer
   with a placeholder link (`footer`), so the sender sees what is added; the footer is not part of
   what confirmation compares.
4. **Public unsubscribe on the portal server.** `GET /mailing-unsubscribe/{token}` returns the
   company name, the address masked (`j***@example.com`), the language of the mailing and whether
   the address is already unsubscribed; reading changes nothing, so mail scanners that open links
   do not unsubscribe anyone. `POST /mailing-unsubscribe/{token}` puts the address on the register
   with source `unsubscribe_link` (idempotent) and answers 204. An unknown token is a 404 that
   reveals nothing. The routes are mounted on the portal server of
   [ADR 0050](0050-portal-surface.md) next to the satisfaction survey and fall under its per-client
   rate limit; no sign-in is needed, the link is the credential. A new entry is audited without a
   user (`audit::record_system`), with the address, mailing and customer in the event data.
5. **Staff manage the register.** `GET /customers/mail-merge/opt-outs` lists the company's
   addresses, newest first; `POST /customers/mail-merge/opt-outs` with `{email}` adds one (checked
   like a recipient address, normalised, source `staff`, idempotent);
   `DELETE /customers/mail-merge/opt-outs/{email}` takes one off again when its owner asks to
   receive mailings again, which only staff can do. Both changes are audited (`mailing_opt_out`,
   `added` / `removed`). The permissions are those of the mail merge draft (`customers.write` and
   `kb.read`).
6. **App.** `MailMergePage` labels the `opted_out` problem like the others, shows the footer under
   each recipient's message and opens the register in a dialog (list, add, remove); a change to the
   register marks the preview as out of date. The customer portal has a page `/unsubscribe` that
   reads the token from the address fragment, writes in the language of the mailing and shows the
   company and masked address, an unsubscribe button and then a confirmation, or that the address
   is already unsubscribed or the link is not valid.
7. **Clones.** The anonymise script replaces the addresses on the register with synthetic ones.

**Consequences.**

- An opt-out is tied to an address, not to a customer or contact: a customer that changes its
  address is mailed at the new one, and an address used by two customers is unsubscribed for both.
- Deferred: no `List-Unsubscribe` header, because the outbox has no custom headers; no records of
  explicit opt-in consent, so prospects without a customer relationship cannot be mailed on this
  basis; and no per-topic preferences, so an opt-out stops all mail-merge mailings of the company.
- System mail that is not marketing (portal login links, survey links, ticket replies) does not
  look at the register.
- A token in a forwarded mail lets its holder unsubscribe that address; that is accepted, as for
  the survey links, because the only effect is fewer mailings and staff can undo it.
