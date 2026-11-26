# 0098 — Document library and customer mail merge

**Status:** Accepted (retrospective; DL1 of the roadmap, PR #131; builds on [ADR 0018](0018-knowledge-base.md),
[ADR 0017](0017-helpdesk-sla-teams-attachments.md) and [ADR 0048](0048-environment-clones-and-outbound-safety.md))

**Context.** Technical memos and product presentations exist as finished PDFs, often one per
language. Staff kept them outside the system, attached them to helpdesk replies by uploading the
same file again, and sent them to customers one e-mail at a time. Nothing recorded which revision a
customer had received, and a corrected memo could not replace the old one without losing track of
what had gone out.

**Decision.** The library and the mail merge live in the knowledge-base crate (`tradocraft-kb`,
modules `documents` and `mail_merge`); migrations `20270225000001_kb_documents.sql` to
`20270225000004_customer_mail_merge_queue.sql`.

1. **A library document is metadata plus uploaded PDFs.** `kb.documents` holds a title, a `kind`
   (`technical_memo` or `product_presentation`), free `keywords` and `product_codes`; every product
   code must exist in `products.products`. The PDF itself is not generated: an administrator
   uploads finished files (`PUT /kb/documents/{id}/draft/{language}` with the raw bytes, which must
   start with `%PDF-`, at most `MAX_FILE_BYTES`) in one of the five languages `en`, `nl`, `fr`,
   `de`, `es`. Files are stored through `core::files::store_document` in the blob store; a
   `kb.document_pdfs` row links document, revision and language to a `core.files` row.
2. **Revisions.** `kb.document_revisions` numbers revisions per document; a unique partial index
   allows at most one unpublished (draft) revision. The first upload after a publication opens
   revision *n + 1* and copies the language files of the published revision into it, so a draft
   starts as the published set and only the uploaded languages change. Uploading the same bytes
   and filename again is a no-op; replacing a draft file deletes the old `core.files` row when no
   other revision refers to it (the blob is left to the orphan sweep, which the upload holds off
   with the shared advisory lock it already uses for ingest). `POST /kb/documents/{id}/publish`
   stamps `published_at` on the draft; without a draft it is a 422. Published revisions are never
   changed, so a file reference taken from one stays valid.
3. **Visibility.** `kb.read` lists, opens and downloads documents that have a published revision,
   and sees only published revisions. `kb.admin` also sees documents without one and the draft
   revision, and is the only right that creates, uploads and publishes. Searching (`q`) matches
   title, keywords and product codes; the list returns at most 100 documents. Downloads are sent
   `private, no-store` with `nosniff`. Everything is scoped to the user's company.
4. **App.** `DocumentLibraryPage` (`/kb/documents`, linked from the knowledge base) lists, creates
   and uploads (shown to `kb.admin` only), downloads, and previews a revision in a dialog with the
   `printing` package's `PdfPreview` (actions off). Each PDF row shows language, revision and
   "draft" when unpublished.
5. **Helpdesk replies** can attach published library PDFs without uploading them again: the reply
   carries `library_pdfs` (document, revision, language). `link_library_pdfs` requires `kb.read`,
   creates a ticket attachment with its own `core.files` row that shares the immutable blob, and
   records the variant in `helpdesk.ticket_attachments` (`document_id`, `document_revision`,
   `document_language`, foreign key to `kb.document_pdfs`). Library PDFs count towards the ten
   files per message, and the same variant cannot be attached twice.
6. **Mail merge draft.** One saved draft per user and company (`crm.mail_merge_drafts`): a
   published document revision, a subject and plain-text body per language, and an optional
   contact choice per customer. Subjects have no line breaks and at most 500 bytes; bodies at most
   32 000. `GET` and `PUT /customers/mail-merge` return the draft with a preview of the audience;
   a preview never queues mail.
7. **Audience.** Every active customer that has commercial terms (`crm.customer_terms`) with the
   company. Per customer the recipient is the chosen active contact, the only active contact, or,
   when the customer has no active contacts, the customer's own e-mail address; a contact's
   address is its primary e-mail. The language is the contact's, else the customer's. Each row
   lists its problems: `select_contact` (several contacts, none chosen), `missing_address` (none
   or not usable), `missing_translation` (no subject and body in that language), `missing_pdf` (the
   revision has no PDF in that language) and `duplicate_address` (two rows would go to the same
   address). Only rows without problems are sent; the others are shown and skipped.
8. **Placeholders.** `{{customer.name}}` and `{{contact.name}}` (the customer's name when no
   contact is selected) are replaced in subject and body. Unknown tokens are left as written, and
   replacement works on the original text only, so a name containing braces is not expanded again.
9. **Approve, then send.** Saving a draft stores the preview as `approved_preview` with a new
   `approval_id`; when the preview is unchanged the earlier approval id is kept.
   `POST /customers/mail-merge/{approval_id}/confirm` locks the draft row, refuses (409) an
   approval id that is not the current one, builds the preview again and refuses (409) if the
   eligible recipients (customer, contact, address, language) differ from what was approved. It
   then writes `crm.mailings` (id = approval id, sender, document, revision) and, per eligible
   row, one `core.mail_outbox` message with the rendered subject and body and the PDF of that
   language attached by storage key, plus a `crm.mailing_deliveries` row. It is one transaction:
   all messages are queued or none. Confirming the same approval id again does nothing.
10. **Sending** is the worker's existing system-mail pass over the outbox; no mailbox is set, so
    the fallback transport is used. Outside a live environment that transport writes files
    (outbound policy of [ADR 0048](0048-environment-clones-and-outbound-safety.md), following
    [ADR 0043](0043-environments.md)), so a test or tutorial environment cannot reach customers.
    A failure to read the attachment blob is now recorded on the message like any other delivery
    failure instead of aborting the pass.
11. **History.** `GET /customers/mail-merge/history` lists the user's own mailings per recipient
    with address, subject, PDF name and the outbox delivery state and error.
12. **Permissions.** Draft, preview and history need `customers.write` and `kb.read`; confirming
    also needs the new `mail_merge.send` (module Customers), which no built-in role except `admin`
    grants. `MailMergePage` (`/customers/mail-merge`, from the customer list) shows the send button
    only with `mail_merge.send`.
13. **Clones.** The anonymise script clears every `approved_preview`, so a clone must rebuild its
    previews from the anonymised contacts before anything can be confirmed, and overwrites the
    subject and body of queued mailing messages.

**Consequences.**

- The library stores PDFs made elsewhere; nothing is rendered from templates, and the document's
  text is not searchable.
- Documents cannot be renamed, deleted or unpublished, and a language cannot be removed from a
  draft once it is there (it is copied from the published revision); these need endpoints of their
  own.
- The mail merge always targets the whole audience of the company; filtering by segment, tag or
  product is deferred. Opt-outs and the unsubscribe link are in
  [ADR 0099](0099-mail-merge-opt-out-and-unsubscribe.md).
- One draft per user means a second mailing replaces the first draft; mailings already confirmed
  are kept in the history.
- Mail merge rows reuse the system-mail outbox and its retry and failure reporting; there is no
  per-mailing throttling.
- Bodies are plain text with two placeholders; formatting and further fields are deferred.
