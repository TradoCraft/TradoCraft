# 0060 — Work centres, routings and operations: where and how a production order is built

**Status:** Accepted

**Context.** Production orders ([ADR 0036](0036-production.md)) said what to build and from what, but
not where or how: no work centres, no routing on the BOM, no operations on the order, no
labour, no capacity and no cost beyond the standard cost of the components. This is C1b of the roadmap.
The work-centre planning board (finite loading, drag and drop) is the work-centre half of C3 and stays
open.

**Decision.** Migration `20270202000001_production_routings.sql`, in schema `production` and crate
`tradocraft-production`. No new module and **no new permissions**: the four `production.*` rights and
`inventory.cost` cover everything (below). Every new top-level table carries `company_id`, with composite
foreign keys `(x_id, company_id)` as in ADR 0049. Every change is audited.

* **Work centres** (`production.work_centres`: code, name, division, `capacity` = parallel units,
  `cost_per_hour`, active). Kept by the administrator (`production.admin`, like divisions); read by
  everyone who sees production. One that routings or operations use is deactivated, not deleted (409),
  and a division with work centres cannot be deleted. **Opening hours** (`work_centre_hours`: several
  blocks per weekday; none means Monday to Friday 08:00-12:00 and 13:00-17:00) and **closures**
  (`work_centre_closures`: a date range for one work centre, or for the whole plant when none is named;
  maintenance, holiday or other) are tables of their own, not `planning.*`: the planning calendar is
  keyed by user, its permissions belong to the Field module, and several of its queries read
  `user_id IS NULL` as "company default", so a second resource kind would have needed a rewrite of that
  module. Planners (`production.write`) enter closures; the administrator keeps the hours.
* **Routing on the BOM revision** (`production.routing_operations`: position, name, work centre, setup
  minutes once per order, run minutes per unit of the stock unit). It hangs off `engineering.boms.id`, so
  it is frozen with the revision: editable (`PUT /boms/{id}/routing`, replace-all) only while the
  revision is a draft, by whoever holds `bom.write` **and** `production.read` (the second keeps it off
  where the Production module is off, since `bom.write` belongs to Engineering). BOMs are shared master
  data without a company, so each company keeps its own rows for a BOM. A work centre that was
  deactivated cannot be put into a routing, but one the routing already has stays when it is saved again.
  `GET /boms/{id}/routing` needs `production.read`.
  **Deliberate exception to the layering:** `engineering::bom::create_bom` copies the routing rows of the
  revision it copies from (the active one, or `copy_from`) with one `INSERT .. SELECT` in the same
  transaction, for every company. Production depends on engineering, so engineering cannot call it, and
  a new revision that silently lost its routing when it was activated would be worse than one write into
  production's table (the reverse of the sales cancel guard that reads `production.production_orders`,
  ADR 0036). The queries are runtime strings, so there is no compile-time coupling.
* **Operations on the production order** (`production.order_operations`). **Release** copies the routing
  of the frozen BOM revision (name, work centre, setup, run time, the work centre's `cost_per_hour` as
  `cost_rate`), computes the planned minutes for the order quantity (setup + run x quantity, rounded up)
  and schedules them; the component standard costs are frozen too (`order_components.standard_cost`), so
  planned and actual cost do not move when a standard cost or a rate changes later. An order without a
  routing has no operations and works exactly as before. Status `pending` → `in_progress` → `done`, or
  `skipped`. Starting the first operation starts the order (and the sales order follows, ADR 0036).
* **Scheduling** is a pure module (`schedule.rs`, unit-tested): date granularity, **infinite capacity**
  (other orders' load is not looked at), operations in order, each taking the working minutes of its work
  centre's calendar day by day (closures skipped; the next operation may start on the day the previous one
  ends while minutes are left, counted against the next work centre's day length). An operation runs on
  one unit; `capacity` only widens what a day offers. A work centre with no working time within two years
  refuses the release with 422. It starts from `start_date` (default today), or after the last subassembly
  is ready. **The planned-ready date is never set by the schedule**: it moves the sales order to `planned`
  and is the basis of the promised date, and the schedule ignores load and shortages. The order carries
  the derived `scheduled_end` (the end of its last open operation) and `behind_schedule` (a planned-ready
  date earlier than that); the app offers `scheduled_end` as the date to take over. `POST
  /production-orders/{id}/schedule` places the operations that have not started again (a running one holds
  the work until its planned end); `PUT .../operations/{id}` moves one to another active work centre
  (refreshing its rate) or other dates.
* **Labour is a completion total.** `finish` records the total minutes worked (default: the planned
  minutes) and who finished it; no per-person entries, no timers. `reopen` takes a finish back. Operations
  can be finished out of order. **Completing an order never waits for its operations**: the completion
  dialog lists the open ones with their planned minutes; the ones whose minutes are filled in are finished,
  the others are `skipped` with nothing recorded (`CompleteProductionInput.operations`; an older client
  that names none skips them all). Operation start, finish and reopen need `production.run`; moving and
  scheduling `production.write`.
* **Capacity** (`GET /production/capacity?from&to&division_id`, at most 62 days): per work centre and day,
  `available_minutes` (the day's block minutes x capacity, 0 on a closure) against `load_minutes` (the
  planned minutes of every open operation of an open order, spread over the working days between its
  planned dates in proportion to what each day offers; work planned to end before the period counts on its
  first day; a running operation counts in full, as no progress is recorded) and an `overloaded` flag.
  Operations of cancelled and completed orders do not count.
* **Multi-level auto-release.** `auto_release_subassemblies` on the release inserts the order first, then
  releases a production order below it (`parent_order_id`, built for stock, so the sales order's line and
  status maths are untouched) for every component that is built from a BOM and that stock could not
  reserve, for the **shortfall**: required minus what is free to reserve (`inventory::reservations::
  free_to_reserve`, sharing the candidate query of `allocate`). It recurses up to five levels in one
  transaction; any failure undoes everything. The parent's own work is scheduled after the last
  subassembly's end. `POST /production-orders/{id}/components/{component_id}/build` does it for one
  component of an existing order (required minus reserved, free and what open subassembly orders already
  cover, 409 when that is nothing) and replaces the quantity the app used to guess. A fractional need for
  a serial-tracked component was already refused at release (it cannot be reserved), so a shortfall is
  always whole.
* **Cost** needs `inventory.cost` (administrator, product manager, purchaser) and, because that right
  belongs to the Products module, also `production.read`. `GET /production/products/{id}/cost-rollup?
  quantity=` walks the active BOM and routing through every level: bought components at their standard
  cost (a subassembly is costed from its own BOM and routing, not from its standard cost), operation minutes
  at the work centre's current `cost_per_hour`, a breakdown per level, and the products or work centres
  that have no cost listed as `gaps` instead of counting as zero. A production order shows `planned_cost`
  (components at their frozen cost, operations at planned minutes and frozen rates) and, once it has
  started, `actual_cost` (consumed and scrapped quantities, booked at completion, and the minutes of
  finished operations); both are absent for everyone else, as is every `cost_rate` and `cost_per_hour`.
  The stock ledger still books output at the product's standard cost: valuation at actual cost and work in
  progress are not part of this.
* **Traveller** (`GET /production-orders/{id}/pdf?lang=`, `production.read`): `templates/
  production_order.typ` in five languages: the product, quantity, BOM revision, sales order, customer,
  priority and planned-ready date, the internal production remark of the order line (which orders now
  carry as `production_remark`), the components to pick, the operations with room for the minutes worked
  and a tick, the subassembly orders and a line for the lot or serial numbers. The language is `?lang`,
  else the user's own (`core::company::user_language`), else the company's; there is no customer. Cost is
  never printed.
* **Flutter**: work centres page (list, edit, working hours, closures), capacity grid (two weeks, a week at
  a time, per division), a routing editor in the BOM tab (draft only, saved together with the lines, the
  routing first) with a cost roll-up dialog, and on the production order: operations with start, finish
  (minutes), reopen, move and schedule again, the behind-schedule banner, subassembly orders, the remark,
  cost and a PDF button. The queue shows how many operations are done and what is behind schedule. The
  release page and the build-for-stock dialog get the auto-release switch. Nothing is rendered for an
  order without operations, so the browser tutorial (which builds a product with no routing) is unchanged.

**Not done yet.** The work-centre planning board (finite loading, drag and drop, the planning calendar
shared with technicians: the work-centre half of C3, which should reuse `ResourceBoard` and the closures
here); operations overlapping or running in parallel, lead-time offsets and alternative routings; per-person
time entries, timers and an offline queue for the shop floor; consuming components at the operation that
needs them; valuation and work in progress at actual cost, and booking output at the rolled-up cost;
editing a routing on an active revision (each correction is a new revision); using routing times and
lead times in MRP (C2); a notification to the production team; a seeded routing and a tutorial chapter;
and the planned-ready date still being set by hand.
