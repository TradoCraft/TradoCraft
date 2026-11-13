# 0037 — Quotation line remarks, remark history and product options

**Status:** Accepted

**Context.** Salespeople repeat the same notes on the same products: a production instruction
("paint RAL 5010, weld the frame first") that the workshop must see, and a remark for the customer
("delivered on a pallet"). The text differs per customer and language, and people want to reuse what
was written before. Separately, products have options that normally go with them (a frame, a
controller, a coating); until now a salesperson had to add every option line by hand, and the
Flutter quotation screen flattened the structure that ADR 0033 introduced.

**Decision.** Migrations `20270120000001_quote_line_remarks.sql` and
`20270120000002_product_options.sql`; code in `crates/sales/src/{remarks,service,orders,pdf,
order_doc}.rs`, `crates/products/src/{options,csv,lib}.rs` and the Flutter quotation and product
screens.

### 1. Two remarks per line

* `sales.quotation_lines` and `sales.order_lines` get `production_remark` and `customer_remark`
  (`text NOT NULL DEFAULT ''`, at most 2000 characters, validated with the other line fields).
  `products.products` gets `default_production_remark`; a new line whose production remark is empty
  starts with the product's default when it is priced.
* The **customer remark is printed** under the description on the quotation PDF and the order
  confirmation. The **production remark is internal**: it is neither part of the document data nor
  of the portal order lines, so a customer can never see it. Staff see both in the app and the API.
* Remarks travel with the line everywhere lines are copied: the update (`PUT` replaces the lines, so
  clients resend them), revisions with `keep` and `current` pricing, the order created from a
  quotation, and order revisions. Configured-quotation imports and the shipping line have none.
* CSV export and import of products gain the `default_production_remark` column (20 columns,
  ADR 0029).

### 2. Remark history

`GET /products/{id}/remark-history?kind=production|customer&scope=customer|language|all`
(`quotations.read`) returns the distinct texts used on earlier lines of that product with the quote
date of the last use, the number of lines and the last quotation number, newest first (50 at most),
limited to the caller's company. Scope `customer` needs `customer_id` (that customer's quotations),
`language` needs `language` (quotations whose customer language equals the current quotation's),
`all` has no filter. Empty remarks are left out; a missing parameter or unknown value is a 422.
The app opens it from a button in each remark field as a dialog with three tabs (this customer, this
language, all); tapping an entry fills the field. A migration index on `quotation_lines (product_id)`
keeps the lookup cheap.

### 3. Product options

* `products.product_options (parent_product_id, option_product_id, default_quantity, required,
  sort_order, active)`, unique per pair, a product cannot be its own option, cascading foreign keys.
  It is **separate from `product_relations`** (compatibility and suggestion rules, ADR 0027), so
  `evaluate()` and its tests are untouched; relations answer "what goes together or not", options
  answer "what is offered with this product, in what quantity".
* `GET /products/{id}/options` (`products.read`) and `PUT /products/{id}/options` (`products.write`,
  replaces the whole set, audited as `options_replaced`). Existing quotations keep their lines.
* On a quotation, a line input may set `add_options: true`. Pricing then adds the product's
  **required, active** options as option lines (`parent_position` pointing at the line, quantity =
  line quantity × default quantity) directly below the line, skipping options that are already its
  children. The flag is not stored: later saves send the resulting lines. The app uses the
  `GET` endpoint instead, so it can also offer the optional options: required ones are added
  straight away, optional ones are ticked in a chooser dialog, each as a child line with its own
  quantity. Option lines are priced as normal products.
* Removing a parent line removes its option lines (in the app; in the database the composite
  foreign key of ADR 0033 cascades). Orders stay flat (ADR 0033); the co-occurrence statistics
  count option lines like any other line (accepted).
* An option with an indicative price still blocks sending until its price is confirmed, like any
  indicative line.

### 4. Flutter

The quotation screen keeps the structure of stored lines (parent, section, comment, percentage)
when a draft is loaded and saved, which the first Flutter implementation of ADR 0033 did not;
option lines are indented. The product screen gets an Options tab (quantity per unit, required
flag), and the product form a default production remark.

**Consequences.** Both remarks are plain text on the line, so documents stay snapshots. The history
is a read-only aggregate over existing lines, no extra table to maintain.

**Later.** Scaling option quantities when the parent quantity is edited afterwards; options with a
percentage price; showing option lines on orders (needs the order structure of ADR 0033's "Later");
history by product family when a product has no earlier remarks.

### 5. Changing the main product

A main line (no parent) of an editable quotation (draft or new) can change its product in place
("Change product" in the line's actions), using the same product search as adding a line. A sent or
accepted quotation does not offer it: revise first, as for any other edit. Orders are unchanged
(ADR 0016: a different product is a new quotation).

- Kept: position, quantity, line discount, section, comment, customer remark, production remark
  (an empty production remark gets the new product's default from the server, as for a new line),
  and all sub-lines with their quantities; percent-of-parent lines keep their percentage.
- Reset: the stored description. The line is sent without a description override so the server
  names it from the new product in the customer's language. Prices are not kept: the normal pricing
  preview reprices the line (price list of the customer's zone at the quotation's price date). A net
  priced product cannot be discounted, so the discount is cleared and a note says so; an indicative
  product has no confirmed price until the user enters one.
- Options stay. They are never removed automatically. A sub-line whose product is not in the
  active option catalogue of its parent (`GET /products/{id}/options`) is marked "Not offered with
  <code>", but only when that catalogue is non-empty (a product without options leaves its
  sub-items free) and never for percent-of-parent lines. The rule is evaluated from the catalogue,
  so it also marks lines when a saved quotation is reloaded. After a swap a note counts the marked
  lines and offers a Remove button for each; removal (with the line's own sub-lines) is always the
  user's action. Marks never block saving or sending; sending with marked lines only shows a note
  afterwards.
- After a swap, the options of the new product that are not on the line yet are offered in the
  options chooser (required ones ticked). The server does not refuse a quotation that lacks a
  required option: required options are only added when asked for (`add_options`).
- Catalogues are cached per screen and refetched for the new product; a failed fetch marks nothing
  and never blocks editing.

