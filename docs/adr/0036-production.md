# 0036 — Production: production orders from the BOM, reservation, backflush and output

**Status:** Accepted

**Context.** Confirmed orders could be delivered ([ADR 0035](0035-delivery.md)) but nothing built
what they asked for: nothing set an order to `in_planning`, `planned`, `in_production` or
`ready_for_shipping`, the BOM of a manufactured product was never used, and the virtual locations
`production_consumption` and `production_output` and the reservation type `production_component`
([ADR 0019](0019-inventory-stock-ledger.md)) had no user. This is C1a of the roadmap: production
orders. Work centres, routings, operations and capacity (C1b) come later.

**Decision.** Migration `20270117000001_production.sql`, new crate `tradocraft-production`, schema
`production`, module `production` (needs sales, inventory and engineering; off where one is off).
Production never writes `sales.*`, `inventory.*` or `engineering.*` directly.

* **Divisions** (`production.divisions`, kept by the administrator with `production.admin`): the
  teams orders are queued for; a product has a default division (`production.product_divisions`).
  A division with production orders is deactivated, not deleted. A production order without a
  division is allowed.
* **Production orders** (`production.production_orders`, numbered `MO2027-00001`): a product, a
  quantity in the stock unit, the **BOM revision frozen at release** (a later revision never changes
  an open order), a division, an optional planned-ready date, and optionally the sales order line it
  builds for (without: build for stock) or the production order it is a subassembly of. Status
  `released` → `in_progress` → `completed`, or `cancelled`.
* **Release** is manual: a planner lists `GET /production/to-release` (manufactured or configurable
  lines of confirmed orders that production orders do not cover yet, most urgent first) and releases a
  line, or builds a product for stock. Releasing explodes the active BOM **one level**
  (`engineering::bom::active_bom_lines`): each component needs BOM quantity × order quantity ×
  (1 + scrap %), rounded up to four decimals. A subassembly is an ordinary component; one that is
  short and itself built from a BOM can get a child production order with one click.
* **Reservation.** Each component is reserved at release (`inventory::set_reserved`, reference type
  `production_component`, reference = the component row). It is all or nothing per component: a short
  component stays unreserved and is flagged (`short`), and `POST /production-orders/{id}/reserve`
  tries again.
* **Completion** (`POST /production-orders/{id}/complete`, `production.run`) is one transaction:
  backflush consumption of the reserved components with the actual quantities, scrap on top
  (reason `scrap`, to the `scrap` location), stock beyond the reservation from a location the planner
  names, and the output into stock (receipt, reason `production_output`): a lot for lot-tracked
  products, and for serial products one unit per serial number, registered with the frozen BOM
  revision. Serial components are chosen unit by unit (`.../components/{id}/serial-units`) and
  attached to the units that were built (`engineering::serials::attach_component_in`, extracted from
  the HTTP handler), evenly, so the as-built genealogy ([ADR 0011](0011-bom-revisions-and-serial-genealogy.md))
  exists from the start. Whatever is still reserved is released. Completing less than ordered closes the
  order with the shortfall visible; another production order covers the rest. Output is booked at the
  standard cost for now.
* **The sales order follows** (`sync_order_status`, after every change): all production orders
  planned-ready dated → `planned`, otherwise `in_planning`; any started → `in_production`; all
  completed → `ready_for_shipping`, which is what delivery waits for. The order never goes back, and
  the promised date (`sales.orders.promised_date`, shown on the order screen) is the latest
  planned-ready date once every open production order has one.
  `sales::orders::set_production_status` is the only way production touches the order. A sales order
  is cancelled in `in_production` only while none of its production orders is open: the status never
  goes back, so an order whose production orders were all cancelled would otherwise be stuck. Sales
  cannot depend on production, so that guard reads `production.production_orders` directly. The
  to-release list reads orders with `sales::orders::delivery_head` (no row lock) and does one
  query set per line, bounded by its 200 orders. Cancelling an earlier one does not cancel its
  production orders (sales does not know production): they show `order_cancelled`, cannot be
  completed, and the planner cancels them, which releases the reservations. Queues sort by the
  priority of the sales order (expedite, normal, low), then the planned-ready date, at read time, so a
  priority change needs no hook.
* **Permissions** (module Production): `production.read` (production, sales, sales manager, support,
  warehouse, product manager, viewer), `production.write` release, edit, reserve and cancel
  (production, sales manager), `production.run` start and complete (production, warehouse) and
  `production.admin` divisions (admin). Every change is audited.
* **Flutter**: the production queue (division, status, priority, shortage flag), the to-release list,
  the production order screen (components with reserved and short, division, planned-ready date,
  start, complete dialog with output, actual consumption, scrap and serial units, cancel), a
  Production section on the order screen, and the divisions page.

**Not done yet.** MRP and availability with open production orders and purchase orders (C2);
work in progress and valuation at actual cost; phantoms and alternative components; notifying the
production team; the portal showing the promised date; and the product's default division in the Flutter
product screen (the API has it). Work centres, routings, operations, labour, capacity, multi-level
auto-release, a production order PDF and the cost roll-up came with C1b
([ADR 0063](0063-work-centres-routings-and-operations.md)); the work-centre planning board is the
work-centre half of C3.
`ready_for_shipping` means every production order of the order is done: a planner must release all
its manufactured lines first.
