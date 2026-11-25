# 0091 — Material requirements planning

**Status:** Accepted (in implementation; C2 of the roadmap; builds on [ADR 0019](0019-inventory-stock-ledger.md),
[ADR 0031](0031-purchasing.md), [ADR 0036](0036-production.md) and [ADR 0063](0063-work-centres-routings-and-operations.md))

**Context.** Stock, purchasing and production each know a part of the answer to "what must be
bought or built, and when". Products carry a reorder level, a maximum and a lead time that nothing
reads; a short component is only found when a production order is released
([ADR 0036](0036-production.md)); a planner works it out by hand from the order list, the stock list
and the open purchase orders.

**Decision.** A crate `tradocraft-mrp` (schema `mrp`, migration `20270305000001_mrp.sql`).

1. **A run proposes, a planner decides.** `POST /mrp/runs` plans the whole company over a horizon (90
   days, at most 730) and keeps **proposals**: to buy a purchased product or to build a manufactured
   one. Nothing is ordered by itself. A run replaces the open proposals of earlier runs (they become
   `superseded`, kept for the record); converted and dismissed ones stay as they are. The run is one
   request, on one repeatable-read snapshot, and it is the only writer of a company's proposals at a
   time (item 8); moving it to the worker is not needed at this size.
2. **What counts**:
   * *requirements*: the open quantity of every line of the confirmed revision of an order that is
     being worked on (`confirmed` to `partially_shipped`), less what has shipped, due on the
     promised date or else the order date; the components that production orders in progress still
     take, from the day the order's work starts (`production_orders.planned_start_date`, set at
     release and when the order is scheduled again; an order without one counts as today): they
     are reserved but still in the warehouse;
   * *receipts*: open purchase orders (approved, sent, partially received; a draft is an intention)
     due on the expected delivery date, and released or in-progress production orders due on their
     planned-ready date;
   * *stock*: what is in the active normal warehouses, reserved stock included (what is reserved is
     a requirement of an order, counted once there). Services are not planned.
3. **The projection** (`engine`, pure and unit-tested). Per product, day by day: stock, plus receipts,
   less requirements. Past-due items count as due today; items after the horizon are ignored. When
   the projection falls below the **floor** (the larger of `safety_stock` and `reorder_min`), a
   proposal is made for the shortfall, topped up to `reorder_max` when that is set, at least the
   supplier's minimum order quantity, rounded up to `order_multiple`. It is placed one lead time
   before the need date but not before today; when that is not enough it is flagged `late`. A
   proposal counts as supply at once, so one shortage is covered once. `reason` says whether a
   requirement is uncovered (`demand`) or only the floor is not kept (`safety_stock`), and `pegging`
   lists the requirements it serves.
4. **Down the bills of materials.** A product with an active BOM (manufactured or configurable) is
   built; anything else is bought, from its preferred supplier (its minimum order quantity and lead
   time win over the product's). Products are planned from the top down, so a proposal to build is a
   requirement for its components on the day the build has to start, with the scrap allowance, and
   those components get proposals in turn, to any depth. A BOM that calls itself is refused (422).
5. **Lead times are calendar days.** A built product's lead time is its `lead_time_days`; the
   routing times and the work centres' calendars of [ADR 0063](0063-work-centres-routings-and-operations.md)
   are not used, and no supplier calendar exists. Both are later work.
6. **Planning parameters on the product:** `safety_stock` and `order_multiple` (new, with the existing
   `reorder_min`, `reorder_max` and `lead_time_days`), in the product form and API.
7. **Conversion.** `POST /mrp/proposals/{id}/convert`: a purchase proposal becomes a **draft** purchase
   order (the supplier of the proposal or one given; the price of the supplier product, else the
   standard cost; expected on the need date); a production proposal becomes a **released** production
   order for stock (ready on the need date, started on the order date; its components are reserved as
   for any release, and the subassemblies that are short have proposals of their own). Nothing is
   approved or sent. `POST /mrp/proposals/{id}/dismiss` sets it aside. Both are audited.
8. **One writer at a time.** A run, converting a proposal and dismissing one take the company's
   planning lock (`pg_advisory_xact_lock(hashtextextended('mrp:<company>', 0))`). A conversion that
   meets a run waits for it and finds its proposal replaced (409); a run waits for a conversion and
   then sees the order it made, so it does not propose the same thing again. The run holds the lock as
   a session lock on a connection of its own, taken before its snapshot starts (a lock waited for
   inside a repeatable-read transaction is waited for with a snapshot that does not show what the
   holder commits), in a task that a client going away cannot cancel. Other companies do not wait.
9. **Paged list.** `GET /mrp/proposals` returns at most `limit` proposals (default 100, at most 500),
   ordered by the day to order, the need date, the product code and the id; `after` takes the id of
   the last proposal of the page before. The app shows "show more" while a page is full.
10. **No permission of its own.** Running and acting on a production proposal need `production.write`,
   a purchase proposal `purchasing.write`; reading needs `production.read` (what is built) or
   `purchasing.read` (what is bought), each seeing only its kind.

**Consequences.**

- Sales orders have no date per line, so a whole order is due on one day; a line that can wait is
  planned as early as the rest. A per-line date is a later addition.
- Stock is one number per product: lots, locations and expiry dates are not looked at, and expired
  lots still count as stock.
- Components are rounded the way a release rounds them (up to four decimals,
  `production::orders::required`), so a proposal asks for what the production order will need.
- A dismissed proposal is not remembered: the next run proposes the same shortage again when it is
  still there.
- A run is a consistent picture of the moment its snapshot was taken; orders entered while it runs
  are in the next one. Waiting for another run or a conversion of the same company can delay it.

**Not done yet.** Routing times and calendars in lead times; supplier calendars and order days;
net-change runs and a worker job for large companies; a per-line delivery date; a minimum or fixed
lot size per product beyond the multiple; planning for several warehouses separately; a forecast or
demand from quotations; buying from alternative suppliers; reschedule proposals for orders that
arrive too early or too late.
