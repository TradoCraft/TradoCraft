# 0060 — Incoming supply from open purchase orders

**Status:** Accepted

**Context.** ADR 0019 deferred "open POs/MOs in ATP" to B2 and C1. Availability on an order
(`GET /inventory/orders/{id}/availability`) shows stock on hand less reservations, so a buyer or
planner cannot see that goods for a short line are already on order. MRP (C2) needs the same figure.
`tradocraft-purchasing` depends on `tradocraft-inventory` (receipts post stock moves), so inventory
cannot call purchasing without a dependency cycle, and no module reads another module's tables.

**Decision.** Purchasing owns the figure and exposes it; consumers combine it with availability.

* `purchasing::orders::incoming_for_products(conn, company_id, product_ids)`: per product, the sum
  of `quantity - quantity_received` over open lines, the earliest `expected_delivery_date` among
  them, and the lines (order id and number, open quantity, expected date), ordered by date with
  undated lines last. Products without open lines are left out.
* `GET /purchase-orders/incoming?product_ids=a,b,c` (permission `purchasing.read`, at most 200 ids,
  a malformed id is a 422). This is the endpoint the order stock panel and later MRP read.
* **Which orders count:** `sent` and `partially_received`. A draft or an approved order has not gone
  to the supplier, so it is not a promise. Cancelled and received orders have nothing open.
* **Not part of `available`.** Incoming quantity is shown next to availability and never added to
  it: ATP stays "what is on the shelf and free". A shortfall can be marked as covered by an order
  only in the UI, with its date.
* Quantities are in the stock unit; PO lines have no unit of their own.

**Order screen.** The order stock panel asks for the incoming supply of the lines that are still
short, only for users with `purchasing.read`, and shows "On order: 6, expected 01/03/2027" after the
shortfall. The request is advisory: when it fails the panel shows availability as before, without an
error. Lines that are fully covered are not asked about.

**Still to do.** Production orders as supply follow with C1b/C2.
