# 0084 — Three price flags and corrections of planned prices

**Status:** Accepted (amends [ADR 0012](0012-rebates-price-dates-and-price-changes.md))

**Context.** ADR 0012 gave each product one pricing type: `list`, `net` or `indicative`. The price
lists the company maintains today (exported from its CRM) keep three independent flags per
product instead: *non-discountable*, *price on request* and *price is indicative*. A product can be
both non-discountable and priced on request, which one type cannot say. The meaning differs too:
in TradoCraft `indicative` forced the salesperson to enter the price on every quotation, while in
the source data an indicative price is the normal list price, only printed as indicative (and
rebates apply to it). Forcing a price is what *price on request* means there.

Separately, a price change is a new dated row and rows are never edited (ADR 0012). That keeps the
history honest for prices that are or were in effect, but it also made a typo in a price planned
for next month impossible to fix: a second price on the same start date is refused, and nothing
could delete the wrong one.

**Decision.**

* **Three flags replace `pricing_type`** on `products.products`, and are copied onto quotation and
  order lines so a document keeps the terms it was made with:
  * `non_discountable`: no customer rebate (the rebate source is `net`) and no manual line
    discount. This is the old `net`.
  * `price_on_request`: the product has no list price. Its zone prices, if any, are never used and
    none are needed. A new line has no price (zero, `price_confirmed = false`) until the
    salesperson enters one (`unit_price` on the line), and a quotation with such a line cannot be
    sent. Rebates apply to the entered price unless the product is also non-discountable. A sales
    order is made from a sent quotation only, so it always carries the entered price. This is
    what the old `indicative` did.
  * `price_is_indicative`: the zone list price applies as for any product, rebates apply, and the
    price cannot be overridden on the line. The quotation prints it as indicative. A marker only.
* **Migration.** `net` became `non_discountable`; `indicative` became `price_on_request`, which
  keeps the behaviour existing quotations were made with. Nothing becomes `price_is_indicative`
  by itself: it is a new meaning and has to be set where it applies.
* **API and CSV.** Products, quotation lines, order lines and repricing lines expose the three
  booleans instead of `pricing_type`; the product CSV has three boolean columns instead of one.
  `GET /products` sorts on each of them.
* **Planned prices can be corrected.** A zone price that has not started yet (`valid_from` after
  today) can be corrected, its price and start date (`PUT /products/{id}/prices/{price_id}`), or
  deleted (`DELETE`). A price that is or was in effect cannot (409): a change to it is still a new
  dated price. Corrections and deletions need `prices.write` and are written to the audit trail
  with the old and new values. Quotations already priced on a planned price keep the price they
  copied, as they always do.
* **Bulk changes can replace planned prices.** With `replace_planned`, a bulk change onto a date
  after today replaces the prices already planned for that date instead of refusing them, and
  computes the change from the price before them, so redoing a wrong bulk change gives the
  intended result. The preview shows the price each line replaces.

**Consequences.** One product can carry any combination of the flags. The product form shows them
as three checkboxes, and the prices tab offers *Correct planned price* (with delete) on prices
that have not started. Printed price lists keep their own per-item flags (ADR 0074).
