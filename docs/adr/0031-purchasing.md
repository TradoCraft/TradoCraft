# 0031 — Purchasing: Suppliers, Purchase Orders, and Goods Receipts

**Status:** Accepted

**Context.** In an industrial manufacturing and engineering business (such as Nordic Industrial Systems),
standard and configurable products rely on bought-in components (motors, gearboxes, electronics, fasteners,
and raw materials). Up to now, stock could only be received through manual adjustments or generic receipts,
and there was no way to record vendor price lists, issue Purchase Orders (POs) to external suppliers,
or match incoming deliveries with ordered goods.

Furthermore, material requirements planning (MRP) and production orders require visibility into supplier
lead times and open purchase orders to calculate component availability (ATP) and net requirements.

**Decision.** Migration `20270109000001_purchasing.sql`.

* **New crate `tradocraft-purchasing` and schema `purchasing`.**
  Follows the modular monolith conventions (ADR 0001, ADR 0003). Transactional tables carry `company_id`.
  Foreign modules interact via public Rust functions and REST endpoints, never direct schema queries.

* **Suppliers and Vendor Terms** (`purchasing.suppliers`):
  Company-scoped supplier records: `name`, `code` (e.g. `SUP-001`), `country` (ISO-2), `currency`,
  `payment_terms_days`, `tax_id` (VAT number), `email`, `phone`, `contact_person`, and `notes`.
  Audited on create and update.

* **Supplier Product Catalog & Price Lists** (`purchasing.supplier_products`):
  Cross-reference between `products.products` and `purchasing.suppliers`:
  `supplier_product_code`, `supplier_product_name`, `unit_price`, `currency`, `moq` (minimum order quantity),
  `lead_time_days`, and `is_preferred` flag.
  Enforces uniqueness on `(company_id, supplier_id, product_id)`.

* **Purchase Order Lifecycle** (`purchasing.purchase_orders` and `purchasing.purchase_order_lines`):
  Status lifecycle: `draft → approved → sent → partially_received → received | cancelled`.
  - Numbering allocated via `core::numbering::next_number(conn, company_id, "PO", year)` (e.g. `PO2027-00001`).
  - Lines reference `products.products` with ordered `quantity`, `unit_price`, and tracked `quantity_received`.
  - Only an approved PO can be sent. In this step, sending only changes the status to `sent` (and is audited);
    PDF generation and supplier e-mail dispatch are deferred.

* **Goods Receipts & Stock Integration** (`purchasing.goods_receipts` and `purchasing.goods_receipt_lines`):
  - Numbering allocated via `core::numbering::next_number(conn, company_id, "GR", year)` (e.g. `GR2027-00001`).
  - Receiving against PO lines executes in a single transaction:
    1. Posts stock movement into `inventory.stock_moves` via `inventory::post_move`
       (`kind = "receipt"`, `reason = "purchase_receipt"`, from virtual vendor location to warehouse location,
       storing `unit_cost` and `currency`).
    2. For serial-tracked components (`product.tracking = 'serial'`), registers the received unit via
       `engineering::serials::register_unit` and sets status to `in_stock`.
    3. Increments `quantity_received` on `purchasing.purchase_order_lines`.
    4. Automatically transitions `purchase_orders.status` to `partially_received` or `received`.
    5. Records audit events in `audit.events`.

* **Authorisation & Permissions:**
  New permissions: `PurchasingRead`, `PurchasingWrite`, `PurchasingApprove`, `GoodsReceipt`.
  Mapped to roles in `core::auth::role_grants`:
  - `admin` and `purchaser` hold full purchasing rights.
  - `warehouse` holds `GoodsReceipt` and `PurchasingRead`.
  - `logistics` and `production` hold `PurchasingRead`.

* **Out of scope for this step:**
  - Automated three-way vendor bill matching (deferred until the finance module).
  - Supplier RFQ portal (suppliers receive orders via PDF email).
  - ~~PO PDF generation and e-mail dispatch to the supplier.~~ Done, see the update below.

**Update: PO PDF and e-mail to the supplier.**

* `templates/purchase_order.typ` (nl, fr, en, de, es) renders the order with the pattern of the delivery
  note: `crates/purchasing/src/po_doc.rs` prepares the data and formats the amounts. A draft carries a
  preview watermark and a cancelled order says so on every page.
* `GET /purchase-orders/{id}/pdf?lang=` (permission `PurchasingRead`). A supplier has no language yet,
  so the language is `lang` or else the company's default language.
* `POST /purchase-orders/{id}/send` now also queues the PDF as an attachment in `core.mail_outbox`
  (`core::mail::enqueue_with_attachment`) in the same transaction as the status change and records a
  `mailed` audit event. If the PDF cannot be made, the order stays `approved`.
* A supplier without an e-mail address is not an error: the order is still marked `sent`, nothing is queued
  and the PDF can be handed over by hand (the order screen has a PDF button). Rejecting the send instead
  would break the tutorial, where suppliers are created with a code and a name only.
* Still open: a supplier language and postal address (the document shows name, country, contact and tax
  id), resending a sent order, and approval limits.
