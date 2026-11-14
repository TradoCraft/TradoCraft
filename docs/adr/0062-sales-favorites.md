# 0062 — Sales favorites

**Status:** Accepted (backend; the quotation and favorites screens follow)

**Context.** Salespeople quote the same products again and again: a main product with the same options
and the same comments. Today every line is typed or picked again, and a customer comment written once in
Dutch has to be written again for a French customer. We want to store such a group once, for everybody in
the company, and load it into any quotation.

**Decision.** Three tables in the `sales` schema, an API under `/favorites` (tag `favorites`) in the
`tradocraft-sales` crate, and two new fields on quotation lines. Migration `20270204000001_favorites.sql`.
No new permission and no new module: reading needs `quotations.read`, every change `quotations.write`.

*Scope.* A favorite belongs to the whole company: everybody with quotation rights sees and edits it
(`company_id` on `sales.favorites`, in every query). An unknown id and an id of another company both
answer 404.

*Data model.*
- `sales.favorites`: `id`, `company_id`, `name` (1 to 120 characters, unique per company ignoring case:
  unique index on `(company_id, lower(name))`, a duplicate answers 409), `created_by`, timestamps.
- `sales.favorite_items`: `id`, `favorite_id` (cascade), `position` (1-based, unique per favorite,
  deferrable so an edit can renumber), `parent_position` (NULL for the main item), `product_id`
  (foreign key to `products.products`), `quantity`, `section`, `comment` (the small printed comment, one
  text), `production_remark` (one text, no language), `percent_of_parent` and `percent_base` (same rules as
  quotation lines). No price column: loading a favorite prices it with the normal pricing, with the zone and
  price date of the quotation.
- `sales.favorite_item_remarks`: `(item_id, language)` primary key, `language` checked against the five
  (nl, fr, en, de, es), `text` (not blank, at most 2000 characters). The customer-facing remark exists in
  several languages, the same model as `helpdesk.prepared_answer_texts`.
- The main item's quantity is the default quantity; the other items' quantity is per ONE unit of the main
  item (like `default_quantity` of an option), so the app multiplies by the quantity chosen at load time.
- **Tree depth.** Quotation lines nest to any depth (ADR 0033: `parent_position` may point at any earlier
  line). A favorite stores `parent_position` the same general way and accepts the same depth, so a
  favorite can be made from a line tree as it is. Exactly one item has no parent (a partial unique index
  allows at most one, the API requires one) and it comes first. A favorite holds at most 40 items.
- Products must exist and be active when a favorite is saved (422). An item may keep a product that was
  deactivated afterwards: the favorite is not changed, `GET` returns `product_active: false` for the item
  and the app flags it. Re-saving a favorite does not fail because of such an unchanged item.

*Endpoints.*
- `GET /favorites?q=&limit=&offset=`: summaries (main product id, code, name, activity, option count,
  languages present across the customer remarks, `updated_at`); `q` searches the name and the main
  product's code and name, ignoring case and accents (ADR 0057). Default 50, at most 200.
- `GET /favorites/{id}`: the tree with the remarks per language.
- `POST /favorites`: create from `{name, items[]}`; items carry no ids.
- `PUT /favorites/{id}`: rename and replace the content. An item that sends its `id` keeps it (so lines that
  point at it keep their link), an item without an id is new, a stored item that is not sent is deleted.
  An id that is not an item of this favorite is 422. The remarks sent replace the item's remarks.
- `DELETE /favorites/{id}`: lines keep working (see below).
- `PUT /favorites/items/{item_id}/remarks/{language}` with `{text, overwrite}` (default `false`): adds the
  customer remark of that language to the item. A language that already has a text answers 409 unless
  `overwrite` is true: a translation never silently replaces an existing text. Returns the favorite.
Translation is typed by hand; there is no machine translation. A favorite can be created from a quotation
line tree by the app (it builds the payload); no server shortcut exists.

*Concurrency.* Updates and the remark call lock the favorite row (`SELECT .. FOR UPDATE`).

*New quotation line fields* (`sales.quotation_lines`, `QuotationLineInput`, `QuotationLine`):
- `customer_remark_language` (`char(2)`, nullable, checked against the five): the language the stored
  customer remark is written in. NULL means it matches the quotation language, or is unknown. An invalid
  code is 422; the field is stored empty when the remark is empty.
- `favorite_item_id` (nullable, foreign key to `sales.favorite_items`, `ON DELETE SET NULL`): the favorite
  item the line was loaded from, so a typed translation can update the favorite later. It must belong to a
  favorite of the caller's company (422 otherwise; a foreign id and an id whose favorite was deleted are not
  told apart). Deleting a favorite, or an item through `PUT`, sets it to NULL; the lines stay as they are.
- Carried through: `update_draft` (lines are rebuilt from the client's input, which must send both fields
  again), revise Keep (the stored lines are copied by `insert_lines`), revise Current (`line_inputs`
  rebuilds the inputs, then pricing), the pricing preview (validated, no storage). A configured import
  leaves both NULL. **Converting a quotation to an order does not copy them**: order lines have neither
  field, and an order is no place to edit a favorite from.
- Pricing is unchanged.

*Audit* (`core::audit::record` in the transaction, entity `favorite`): `created` (name, product ids, item
count), `updated` (field changes of the name, product ids, added and removed item ids, item count),
`deleted` (name, product ids), `remark_added` and `remark_replaced` (item id, product id, language). Text
content (comments, production remarks, customer remarks) is never recorded, only the fixed marker
`text_changed` (true or false), as in ADR 0059 and the to-do crate.

**Consequences.**
- A favorite always names the products by id, so it follows renames and price changes of a product; a
  deactivated product is flagged, not removed. A product that is deleted from the database cannot be,
  because of the foreign key (products are deactivated, not deleted).
- Everybody in the company can edit and delete every favorite; there is no owner. A private or per-team
  favorite would be a later rule next to `company_id`.
- A client that saves a quotation with a stale `favorite_item_id` (the favorite was deleted meanwhile in
  another session) gets 422 and must reload the favorites and drop the field.
- "Exactly one main item" is enforced by the API plus a partial unique index; a row-level check that a
  favorite is never empty would need a deferred constraint trigger and was left out.
- The `favorites` tag is new and the portal does not serve it (the portal surface test covers it).
