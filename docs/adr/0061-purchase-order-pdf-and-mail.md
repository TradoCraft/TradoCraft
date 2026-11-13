# 0061 — The purchase order as a PDF and a mail to the supplier

**Status:** Accepted

**Context.** ADR 0031 let a purchase order be approved and marked `sent`, but "sent" only changed
the status: the buyer still had to make a document and mail it by hand, and nothing recorded to
whom the order went. The other outgoing documents (order confirmation, delivery note, service
report) are Typst templates rendered by `tradocraft-documents` and mailed through the outbox.

**Decision.** Migration `20270202000001_purchase_order_documents.sql`; module
`purchasing::document`; template `templates/purchase_order.typ`.

* **Supplier language.** `purchasing.suppliers.language` (`nl fr en de es`, default from the
  country: NL BE -> nl, FR LU -> fr, DE AT -> de, ES -> es, else en; existing suppliers are
  back-filled the same way). It is part of the supplier API and form. A wrong value is a 422.
* **Send.** `POST /purchase-orders/{id}/send` takes `{ to?, lang? }` (both optional, permission
  `purchasing.write`). In one transaction it locks the order, requires `approved`, resolves the
  address (`to`, else the supplier's e-mail) and the language (`lang`, else the supplier's), sets
  `status = 'sent'` with `sent_at`, `sent_by_user_id` and `sent_to`, renders the PDF, queues one
  mail with the PDF attached (`core::mail::enqueue_with_attachment`, sent by the worker) and
  writes the audit event with the address. Nothing is kept when any step fails.
* **No address.** A supplier without a usable address and no `to` is a **409** that names the
  supplier; a malformed `to` or an unknown `lang` is a **422**. In both cases the order stays
  `approved` and nothing is queued. "Usable" is deliberately loose (one `@`, a dot in the domain, no
  spaces): bounces are the mail server's to report.
* **PDF.** `GET /purchase-orders/{id}/pdf?lang=` (permission `purchasing.read`). A draft or approved
  order carries a PREVIEW watermark and a cancelled one CANCELLED, so only the document that was
  mailed looks final. Lines show our code, the supplier's code, quantity with the product's stock
  unit, price and total; the footer block shows subtotal, VAT and total. Goods are delivered to the
  company's address.
* **Mail.** Subject `Purchase order PO2027-00001` in the five languages, a short body naming the
  requested delivery date when there is one and asking for confirmation of receipt and date.
* **App.** The Send button opens a dialog with the address and language prefilled from the
  supplier (empty when the supplier has none, so the server's refusal is shown); a PDF button on the
  order; a "Sent to ... on ..." line once sent; a language field on the supplier form.

**Not done.**
* Suppliers have no postal address, so the PDF shows the name, contact person, e-mail, phone,
  country and tax number only. Adding address fields is a separate, small step.
* A sent order cannot be sent again (there is no resend and no revision of a sent order); a
  correction means cancelling and creating a new one, or telling the supplier directly.
* No approval limits and no supplier confirmation step.
