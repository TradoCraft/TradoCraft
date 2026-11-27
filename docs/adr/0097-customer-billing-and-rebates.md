# 0097 — Customer billing: invoices, correction credits and annual turnover rebates

**Status:** Accepted (built in PR #147 with the review fixes of commit `b16bd7f`; recorded
retrospectively; builds on [ADR 0008](0008-accounting-stays-external.md),
[ADR 0043](0043-environments.md) and [ADR 0046](0046-supplier-invoices-and-three-way-match.md))

**Context.** Sales orders are shipped with delivery notes, but the invoice to the customer was still
made outside TradoCraft. Some customers also have an annual turnover agreement: what they buy in one
calendar year sets a rebate rate for the next, by tiers. Working that out by hand needs the year's
invoiced turnover per customer, less corrections, and only for the products that count. ADR 0008
keeps the general ledger, VAT returns and annual accounts in the external accounting package, and
the finance crate (ADR 0046) is a register, not a ledger. Customer billing has to stay inside that
boundary: TradoCraft makes and numbers the documents and keeps their figures, the accounting package
stays the book of record, and turnover from the years before TradoCraft billed (or outside it) comes
from the accounting balances, not from a reconstruction.

**Decision.** Two migrations in the `finance` schema: `20270228000002_customer_billing.sql`
(documents) and `20270228000003_customer_rebates.sql` (rebates), plus
`20270228000001_product_turnover_eligibility.sql` on products. Code in `tradocraft-finance`:
`billing.rs` and `billing_routes.rs` (documents), `customer_rebates.rs` and `rebate_routes.rs`
(rebates). The supplier invoice register (`invoices.rs`, ADR 0046) is separate and unchanged.

1. **One table for invoices and credit notes.** `finance.customer_documents` has `kind` (`invoice`,
   `credit_note`) and `status` (`draft`, `posted`), and `finance.customer_document_lines` the lines.
   A document keeps its own snapshots: `customer_name`, `seller` and `customer` (name, street, postal
   code, city, country, VAT number, as jsonb), `language`, `currency`, `vat_regime` (`domestic`,
   `domestic_reverse_charge`, `intra_eu`, `outside_eu`), and on each line the product code,
   description, unit, prices, VAT and turnover flag. Later changes to the customer, the company or
   the product do not change a posted document. Money is `numeric` with 2 decimals, rounded half
   away from zero; `gross_total = net_total + vat_total` is a check constraint on header and lines.
2. **An invoice is made from a shipped delivery.** `POST /customer-invoices` takes a
   `delivery_note_id`, a `document_date` and lines of `delivery_line_id` and `quantity` (in the stock
   unit printed on the delivery note, at most 4 decimals). The delivery note must be `shipped`; the
   date may not be before the shipment nor after today. Currency and VAT regime come from the sales
   order, language and customer address from its quotation, the due date from the customer's
   `payment_terms_days` in `crm.customer_terms` (30 without a row), the seller from `core.companies`
   (legal name when set). A delivery line cannot be invoiced beyond what was shipped (counting posted
   invoices; 409). The shipped stock quantity is converted back to the order unit
   (`tradocraft_inventory::ledger::to_stock_quantity`) and quantity and net amount are taken as a
   share of the order line's total, computed cumulatively, so partial deliveries and partial invoices
   of one order line add up exactly to the line total. A changed stock unit or unit conversion that no
   longer agrees with what was shipped or already posted is a 409. Lines without a shipment (freight,
   services, free text) are not possible.
3. **VAT** is zero for the regimes that `tradocraft_core::vat::vat_exempt_for_regime` exempts
   (`intra_eu`, `outside_eu`, `domestic_reverse_charge`). Otherwise it is rounded per rate over the
   invoice and the rounded amount is spread over the lines cumulatively, so every cent of the
   invoice's VAT sits on a line and a partial credit can take it back. The PDF prints the
   reverse-charge or export wording that belongs to the regime.
4. **Credit notes correct one posted invoice.** `POST /customer-invoices/credits` takes the
   `invoice_id`, a date not before the invoice, a required `reason` and lines of `invoice_line_id`,
   `quantity` (in the invoice line's unit) and an optional `net_total`. Per invoice line, posted
   credits may not exceed its quantity, net amount or VAT (409). Without `net_total` the amounts are
   suggested (`auto_amounts = true`): the proportional share of the line's net amount, or all that is
   left when the last quantity is credited; VAT follows the net amount in proportion, or all that is
   left when the whole remaining net is credited. A given `net_total` up to what is left (a price
   correction) is kept as entered. The credit note copies the invoice's snapshots, currency and VAT
   regime and has no due date. The posted invoice detail shows `creditable_quantity` and
   `creditable_net_total` per line.
5. **Draft, post, discard.** A draft has no number and can be discarded (`DELETE`); a posted document
   cannot be changed or deleted, only corrected by a credit note. `POST /customer-invoices/{id}/post`
   checks the draft again under locks: an invoice takes the delivery note and sales order rows
   (`FOR UPDATE`) and recomputes every line, and a line that no longer gives the same quantity and net
   amount fails with `invoice_draft_stale`; a credit note takes the original invoice row and fails
   with `credit_draft_stale` when another credit changed the suggested amounts, or with a 409 when it
   would exceed the line. Posting an already posted document returns it unchanged. Creating an
   invoice or a credit note accepts a `request_id`: a repeated request with the same payload returns
   the same document, a different payload with the same id is a 409 (advisory lock
   `customer-billing-request:<company>:<request>`).
6. **Numbering at posting.** Invoices `INV-<year>-<nnnnnn>`, credit notes `CN-<year>-<nnnnnn>`, from
   the core numbering sequences `INV` and `CN` for the year of the document date; a number already
   taken (for example by a registered historical invoice) is skipped. Numbers are unique per company.
7. **Turnover eligibility is a product property.** `products.products.included_in_turnover` is a
   nullable boolean: null means not yet classified. It is in the product form and API (omitted on
   update keeps it, null clears it) and in the product import column `included_in_turnover`. When an
   invoice is posted, each line takes the product's current value (the products are read
   `FOR SHARE`, so a change waits); an unclassified product stops the posting with
   `turnover_eligibility_unknown`. A credit line inherits the flag of its invoice line, and a credit
   against an invoice line without a verified flag is refused the same way.
8. **Historical invoices are registered, not recreated.** `POST /customer-invoices/legacy` (permission
   `billing.post`) records an invoice issued before TradoCraft, with its original number, date,
   currency, VAT regime, an `evidence_reference` to the reviewed source, and lines with amounts and a
   turnover flag. It is `posted` and `is_legacy` at once, has no delivery note and no PDF, and exists
   only so that a credit note has something to refer to: its lines hold what is still creditable
   after corrections already made in accounting. Its turnover is not counted (it is in the opening
   balance). When an opening cutoff is recorded for its year it cannot be dated after that cutoff;
   without an opening for that year any date in the year is accepted.
9. **Opening balances and cutover instead of a ledger.** `finance.customer_rebate_openings` holds per
   customer and year the eligible sales verified against the accounting package through a `cutoff`
   date (between 31 December of the year before and 31 December of the year; at the year before's
   end only with a zero amount; not after today), with `verified_by` and `verified_at`
   (`PUT /customer-rebates/customers/{customer}/history`). The eligible sales of a customer through a
   date are that opening balance plus the net amount of posted, non-historical documents dated after
   the cutoff on eligible lines, credits negative. Without an opening for the year there is no figure.
   When an eligible line after the cutoff is in another currency than the company's, or a line is
   still unclassified, the figure is withheld rather than mixed or guessed. A credit reduces turnover
   in the year of its `document_date`.
10. **Rebate schedules and tiers.** `finance.customer_rebate_schedules` has a `name`, an
    `effective_year` and `tiers` (threshold in the company currency, rate 0 to 100 with up to 4
    decimals; thresholds and rates both strictly increasing). Name and effective year identify a
    version: changing either means a new schedule; only the tiers of an existing one can be edited. A
    customer is assigned a schedule by name (`finance.customer_rebate_assignments`); for a rate year
    the version with the latest `effective_year` not after it applies. The rate earned is that of the
    highest tier whose threshold the sales reach; below the first tier it is zero.
11. **Rate-year review and approval.** Sales in year Y earn the rate for year Y + 1 (`rate_year`).
    `GET /customer-rebates/customers/{customer}/rates/{year}` shows the eligible sales of the year
    before (only when that year is over), the proposed rate and an approved rate if any.
    `POST /customer-rebates/customers/{customer}/rates` stores the approval in
    `finance.customer_rebate_rates` with the eligible sales and the rate, so these survive later
    changes to the inputs. The schedule version is referenced by its id only; its tiers are not
    copied, so a later edit of that schedule's tiers is not reflected in the stored approval. It
    needs a closed year with an opening balance and an applicable schedule (422). When a rate is
    already approved, nothing is stored again and the review is returned: `approved_rate` is the
    stored rate, while `eligible_sales` and `proposed_rate` are the current calculation, which may
    differ from the figures the approval was based on (those stay in the table, not in the
    response); there is no re-approval.
12. **Concurrency.** Posting a document, registering a historical invoice, saving an opening balance,
    changing an assignment and approving a rate all take the same per-customer advisory lock
    (`customer_rebate:<company>:<customer>`). Approval recomputes the review under that lock and, when
    the request carries the `proposed_rate` and `eligible_sales` the reviewer saw (the app sends both),
    refuses with 409 if either has changed meanwhile. Each is compared only when it is sent: a
    request that omits one skips that comparison, so the approval may store figures other than
    those the reviewer saw. Once figures are relied on, the period is closed: a document with
    eligible, non-zero lines cannot be posted (`turnover_period_closed`) when a rate for the
    following year is approved or the opening cutoff of its year is on or after its date.
13. **Progress on the invoice.** `finance.customer_rebate_settings` (`GET`/`PUT
    /customer-rebates/settings`) switches `show_on_invoices` and holds the wording per language (nl,
    fr, en, de, es defaults; placeholders `{eligible_sales}`, `{rate_year}`, and for the active
    wording also `{next_threshold}`, `{amount_to_next_tier}`, `{next_rate}`; unknown placeholders are
    refused). When enabled, posting an invoice in the company currency stores a `rebate_progress`
    snapshot on it (sales so far this year, the next tier and what is missing, or that the highest tier
    is reached), which the PDF prints. Without a schedule, an opening balance or a complete figure,
    nothing is printed.
14. **PDF.** `GET /customer-invoices/{id}/pdf` renders `templates/customer_invoice.typ` from the stored
    snapshots in the document's language (nl, fr, en, de, es; English otherwise), for documents posted
    in TradoCraft only. It is rendered on request, not stored, and sent with `Cache-Control: private,
    no-store`.
15. **Permissions** (module `finance`, ADR 0028): `billing.read` (list, detail, PDF), `billing.write`
    (create invoice and credit drafts, discard), `billing.post` (post, register historical invoices)
    and `rebates.admin` (all `/customer-rebates/*` endpoints: settings, schedules, assignments,
    opening balances, review and approval). Role `finance` has the three billing permissions, `viewer`
    has `billing.read`; `rebates.admin` is granted only to `admin`. The Flutter app adds "Customer
    invoices" and "Annual rebates" segments to the Finance section (`customer_billing_page.dart`,
    `customer_rebates_page.dart`) and the turnover field to the product form.
16. **Live posting is opt-in per company** (ADR 0043). In a `test` or `tutorial` environment posting
    is open. In the `live` environment `POST /customer-invoices/{id}/post` is refused (403) unless the
    company's UUID is in the comma-separated `CUSTOMER_BILLING_LIVE_COMPANIES` variable of the API,
    which is to be set only once the accounting handoff and invoice delivery for that company work.
    `POST /customer-invoices/legacy` is not checked against that variable: in live it registers
    posted historical invoices for any company, limited only by `billing.post`. Whether to gate it
    as well is a separate decision. A pilot is reconciled in a test environment first; approvals or
    assignments made there count for nothing in live. Every change is audited (`customer_document`
    `created`, `posted`, `discarded`,
    `legacy_registered`; `customer_rebate_settings`, `customer_rebate_schedule`,
    `customer_rebate_assignment`, `customer_rebate_opening` `verified`, `customer_rebate_rate`
    `approved`).

**Consequences.**

- TradoCraft is where customer invoices are made and numbered, but nothing is booked: there is no
  journal, no receivables balance, no payment status and no dunning. The accounting package stays the
  ledger; the opening balances and the cutoff are the seam between the two, and they must be verified
  against it by a person.
- Every rate year needs an opening row for the year before, also when TradoCraft billed the whole
  year (a zero balance at 31 December of the year before that).
- Turnover is counted in the company currency only; a customer with eligible foreign-currency
  invoices after the cutoff gets no figure, no proposal and no progress line.
- An invoice always follows a shipment: deposits, services without a delivery, freight and
  free-text lines cannot be invoiced, and one invoice covers one delivery note.
- A posted document is final; a wrong invoice is corrected by a credit note. A credit does not free
  the shipped quantity: the delivery line stays invoiced, so a delivery cannot be invoiced again after
  a full credit.
- Posting a document with an eligible, non-zero line dated into a period whose turnover has been
  verified or used for an approval is refused; documents with only non-eligible or zero lines are
  not affected. While only the opening is verified, a late document must be dated after the
  cutoff, or the opening balance redone with a cutoff before the document's date and the eligible
  sales verified again against the accounting package through that new cutoff (re-verifying with
  the unchanged cutoff keeps the document refused). Once the following year's rate is approved,
  eligible documents dated in that year stay refused, even when dated after the cutoff or after the
  opening balance is redone; withdrawing or re-approving a rate is not yet available.
- These new tiered annual rebates are separate from the existing per-customer price rebates of
  `crm.customer_rebates` (ADR 0012), which keep working as before.
- An approved rate is stored with its basis but is not yet applied to quotation or order prices by
  the pricing crate; using it is a later step.

**Not done yet.** Sending invoices to the accounting package and over Peppol (ADR 0008); e-mailing
the PDF; receivables, payments and reminders; invoicing several deliveries at once or lines without a
shipment; currency conversion of turnover; applying the approved rate in pricing; withdrawing or
re-approving a rate; rebate settlement credit notes; customer billing pages in the web UI.
