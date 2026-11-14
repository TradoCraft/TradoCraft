# 0046 — Supplier invoices and the three-way match (accounts-payable register)

**Status:** Accepted

**Context.** Purchasing (ADR 0031) ends at the goods receipt; the supplier's invoice still arrives
on paper or by e-mail and is checked by eye against the order and the delivery note. ADR 0031
deferred "automated three-way vendor bill matching" to a finance module. ADR 0008 keeps the
general ledger, VAT returns and annual accounts in the external accounting package, so this module
must not become a ledger: it registers invoices, tells the buyer whether an invoice agrees with what
was ordered and received, records the approval and whether it was paid, and leaves posting and the
actual payment run to the accounting package.

**Decision.** Migration `20270123000001_finance.sql`; new crate `tradocraft-finance` (schema
`finance`, module `finance`). Purchase orders, goods receipts and suppliers are read only through
public `tradocraft_purchasing` functions (`orders::load`, `orders::numbers_by_id`,
`receipts::received_quantities`, `suppliers::load`, `suppliers::names_by_id`), never by querying the
purchasing tables.

*Tables* (all company-scoped, money and quantities as `Decimal`, ADR 0002):
* `finance.supplier_invoices`: internal number `SI<year>-<seq>` (core numbering code `SI`),
  `supplier_id`, optional `purchase_order_id`, the supplier's `invoice_number` (unique per company
  and supplier), `invoice_date`, `due_date` (default invoice date plus the supplier's
  `payment_terms_days`), `currency`, `status`, `net_total`, `vat_total`, `gross_total`, `notes`,
  `dispute_reason`, `override_reason`, `created_by`, `approved_by` / `approved_at`, `paid_at`,
  `payment_reference`.
* `finance.supplier_invoice_lines`: optional `purchase_order_line_id`, optional `product_id`,
  `description`, `quantity`, `unit_price` (4 decimals), `vat_rate`, and `line_net`, `line_vat`,
  `line_gross` rounded to 2 decimals half away from zero.
* `finance.settings` (one row per company): `quantity_tolerance_pct` (default 0) and
  `price_tolerance_pct` (default 2). Without a row the defaults apply.

*Currency.* An invoice has one currency, which must equal the currency of its purchase order.
There is no conversion; a foreign-currency invoice against an order in another currency is
rejected (422).

*Status lifecycle.* `draft -> matched -> approved -> paid`, plus `disputed`.
* `submit-match` (draft or matched): re-evaluates and sets `matched` when every line is ok,
  otherwise leaves (or puts) the invoice in `draft`; the report is returned either way.
* `approve` (draft or matched): needs a clean match evaluated at that moment. Otherwise it needs an
  `override_reason`; the reason is stored on the invoice and in the audit event. Approving from
  `draft` is allowed when the live match is clean, so `submit-match` is a convenience, not a gate.
* `dispute` (draft, matched or approved): a reason is required; an approval is withdrawn.
  A disputed invoice does not count as invoiced on its order lines.
* `reopen` (disputed or matched): back to `draft` for editing.
* `mark-paid` (approved only): payment date (default today) and payment reference. This records
  that the accounting package or bank paid; the ERP pays nothing.
* Edit (`PUT`) and `DELETE` are drafts only. Every guard violation is a 409. Every state change is
  written with `audit::record` (`created`, `updated`, `deleted`, `match_evaluated`, `approved`,
  `disputed`, `reopened`, `paid`; `finance_settings` `updated`).

*Creating from an order.* `POST /supplier-invoices` with a `purchase_order_id` and no lines
prefills one line per order line from the quantity received and not yet invoiced (all non-disputed
invoices counted, drafts included) at the order price. A duplicate supplier invoice number is a 409.
The order must not be draft or cancelled.

*The match.* A pure function (`finance::matching`) evaluated live, never stored, so a report always
reflects current receipts, other invoices and tolerances. For each invoice line that points at an
order line, with `invoiced` = this line plus every other line on that order line (this invoice's
other lines and all other non-disputed invoices):
* `not_received`: `invoiced > received` (received = sum of the goods receipt lines; no tolerance:
  you do not pay for goods that are not in).
* `over_invoiced`: `invoiced > ordered * (1 + quantity_tolerance_pct / 100)`.
* `price_variance`: `|invoice price - order price| > order price * price_tolerance_pct / 100`
  (so the edge exactly at the tolerance passes; a zero order price tolerates only zero).
* `no_po_line`: a free-text line (freight, services) or an invoice without an order; it cannot be
  matched and is flagged.
* `ok` otherwise. A line carries the first problem as `status` and all of them as `issues`, with
  ordered, received and invoiced quantities, both prices and the variance in percent.
The invoice is `matched` only when it has at least one line and every line is `ok`. VAT, rounding
differences in line totals and the invoice total are not part of the match.

*Permissions* (modules, ADR 0028): module `finance` owns `FinanceRead` (`finance.read`),
`FinanceWrite` (`finance.write`) and `FinanceApprove` (`finance.approve`), and requires
`purchasing`. Read: lists, details and the match report, settings. Write: create, edit, delete,
`submit-match`, `dispute`, `reopen`. Approve: `approve` (including the override), `mark-paid` and
changing the settings. Roles: `admin` all; new role `finance` all three (plus read access to
suppliers, orders, products, stock and reports); `purchaser` and `viewer` `FinanceRead`
(the viewer reads every `.read` permission by design).

*What stays external.* The general ledger, VAT returns, posting of the invoice, the payment run
and the bank reconciliation (ADR 0008). Out of scope for this step: credit notes, Peppol receiving,
exporting approved invoices or payments to the accounting package, currency conversion, PO PDF and
e-mail dispatch, approval limits and multi-level approval, matching against delivery notes of
services. Landed cost, invoice PDFs/attachments and OCR are not part of it either.
