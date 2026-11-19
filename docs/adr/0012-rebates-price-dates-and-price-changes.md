# 0012 — Rebates, pricing types, price dates and price changes

**Status:** Accepted (extends [ADR 0002](0002-money-and-pricing.md); the pricing type and the
"never edited" rule for planned prices are amended by [ADR 0084](0084-price-flags-and-planned-price-corrections.md))

**Context.** Customers get rebates on all products, on a product family or on single products.
Some products have a fixed net price, others only an indicative list price. Customers ask to
update quotations after prices changed, and occasionally a quotation must use last year's prices.

**Decision.**
* **Pricing type per product:** `list` (rebates apply), `net` (fixed net price: no rebate and no
  manual line discount), `indicative` (the list price is a suggestion; the agreed price must be
  entered on each quotation before it can be sent; rebates then apply to it like a list price).
* **Product families** group products for rebates, bulk changes and reporting.
* **Rebates:** the general rebate stays in the customer's commercial terms; product- and
  family-specific rebates (`crm.customer_rebates`) are per company, optionally dated, and may not
  overlap for the same target. For each line the **most specific valid rebate wins**: product,
  then family, then general (`tradocraft_pricing::resolve_rebate`). Each quotation line stores the
  applied percentage and its source, so the document never changes when rebates change later.
* **Price date:** a quotation is priced on the price list (and rebates) valid on its `price_date`,
  normally the quote date. A date before the quote date ("previous price list") needs the
  `prices.backdate` permission (role `sales_manager` or `admin`) and is written to the audit trail.
  Editing a draft keeps its price date.
* **Revising a sent quotation** first shows a line-by-line comparison with today's prices
  (`GET /quotations/{id}/repricing`); the user then chooses `keep` (copies the agreed prices,
  rebates and price date verbatim) or `current` (reprices today; indicative prices must be
  confirmed again).
* **Price changes** are new dated rows, never edits. Bulk changes (`/prices/bulk/preview`,
  `/prices/bulk/apply`) select zones, a family or products, a % or amount, a rounding step and a
  start date that is today or later; they are always previewed and refuse dates that already have
  a price. Quotations priced before the start date are unaffected.

**Later.** Named price lists (separate from the five zones) will plug into the same price
resolution; CSV import will go through the bulk preview/apply path.
