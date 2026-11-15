# 0069 — Price lists

**Status:** Proposed (builds on [ADR 0002](0002-money-and-pricing.md), [ADR 0009](0009-pdf-with-typst.md) and [ADR 0012](0012-rebates-price-dates-and-price-changes.md))

**Context.** A company sends customers a printed price list: products under titled chapters and
groups, in a fixed order, with the prices of one price zone, in the customer's language, as PDF and
as Excel, one file per zone and language, and per chapter or combination of chapters. Today this is made outside the system from a sort order column that encodes the chapter,
group and position as one dotted string, with the company's names, uplift, logo and languages
written into the program. tradocraft has products, price zones and dated zone prices (ADR 0002) but
no document that groups and orders products, and no group titles.

**Decision.**

1. **A list is a layout, never a copy of prices.** Tables `pricing.price_lists`,
   `pricing.price_list_zones`, `pricing.price_list_groups`, `pricing.price_list_items` and
   `pricing.price_list_exports`, all with `company_id`, plus the child tables of the data model
   below (`migrations/20270217000001_price_lists.sql`). A list has a `code` (unique per company), a name
   and a `valid_from` date. It covers **several price zones**: a row in `price_list_zones` per zone
   (unique per list and zone) with a `sort_order`; the languages published for the zone are rows in
   `price_list_zone_languages` (non-empty subset of nl, fr, en, de, es; `sort_order` 0 is the
   default). Prices are looked up at render time
   in `pricing.zone_prices` of the zone being rendered, valid on `valid_from`, with the existing
   `resolve_zone_price` (ADR 0002). A price change after the fact is a new dated zone price, and the
   list shows it by moving its date. Nothing about prices is stored on the list. The zones are
   replaced as a whole with `PUT /price-lists/{id}/zones` (array; request order is print order),
   the simplest form that matches the other handlers, which also replace whole bodies. A zone a list
   is published for cannot be deleted (409).
2. **Explicit groups plus a sort key.** Groups are rows (`parent_id`, `sort_order`, `page_break`)
   with their titles in `price_list_group_titles`. Items carry a `sort_key` (dotted, compared segment by
   segment so `1.2` precedes `1.10`) that orders them inside their group. The sort order of the
   old program is not derived from a string; importing it creates the group rows and sets the keys.
3. **Arbitrary depth, limited to four levels.** The old data has four sort levels. The tree is
   validated on every write (same list, no cycle, depth at most four) while the list row is locked.
   `page_break` is honoured on top-level groups (chapters).
4. **A product can be in several lists** (unique per list and product), each time with its own
   group, key and flags. Items have four flags: `price_on_request`, `net`, `indicative` and
   `hidden`, and an optional description per language (`price_list_item_descriptions`) that replaces the product name.
5. **Assembly is pure.** `assemble()` in `crates/products/src/price_lists.rs` orders groups by
   `sort_order` and items by sort key, then product code. An item is printed when it is not hidden
   and has a zone price or is flagged price-on-request; a price of zero or the flag prints
   ON REQUEST (without NET or indicative markers). A group with nothing printable in itself or
   below it is left out. Text (group titles, descriptions) is taken from the first language in the
   chain requested language, company default language, the list's languages; then any language;
   an item falls back to the product name.
6. **Export profiles.** `price_list_exports` (code unique per list, name, `sort_order`,
   optional `file_name` template) and their chapters in `price_list_export_groups` say which
   chapters go into one file: no chapters is the whole list, one group an individual chapter,
   several a combination. The chapters must be unique top-level groups of the same list: the
   composite foreign keys prove "same list", a trigger proves "top-level", and the API checks
   both first, under the list lock, for a readable 422. **Deleting a group that a profile uses is
   refused (409, naming the profiles), and so is moving it below another group**; the profile must
   be changed first. (The alternative, silently removing the group from the arrays, would change
   what a file contains without anyone deciding it.) Profiles are plain data an administrator edits
   through `/price-lists/{id}/exports` (CRUD); `POST /price-lists/{id}/exports/per-chapter` creates
   one single-chapter profile per top-level group that has none yet (idempotent) and returns all
   profiles. No configuration file is involved.
7. **Rendering and the export plan.**
   `POST /price-lists/{id}/render?zone_id=&lang=&export_id=&format=pdf|xlsx`: `zone_id` is
   required when the list has several zones, `lang` must be one of that zone's languages (default
   its first), `export_id` limits the file to that profile's chapters with all their descendants
   (`select_groups`, then the unchanged pure `assemble()`; chapters keep list order and empty
   groups are skipped). The PDF is `templates/price_list.typ` (ADR 0009); the API passes
   pre-formatted strings (`format_unit_price`) and the labels for the language, so the template only
   lays out and prints exactly the sections it is given. Labels live in
   `crates/documents/src/price_list.rs`, because the Excel export needs the same words. The
   workbook is written with `rust_xlsxwriter`: one sheet, group titles as rows. Inactive products
   are not printed. `GET /price-lists/{id}/export-plan?format=` lists every file to produce:
   per zone, per language of that zone, the whole list and then each profile, as
   `{zone_id, zone_code, lang, export_id (null = whole list), format, relative_path}`. The path is
   `<list name>/<zone name>/<lang>/<profile name or list name>.<ext>` and is computed by the server
   (`crates/products/src/price_list_plan.rs`): every segment is sanitized (separators and Windows
   characters replaced, control and invisible characters dropped, no `..`, no leading dots or
   spaces, no trailing dots or spaces, reserved device names prefixed, capped at 80 characters) and
   clashing paths get ` (2)`. A client writes files below a folder of its choice and never builds
   names from user text.
8. **Per-company presentation** is the `settings` jsonb of the list (footer text, currency symbol,
   accent colour, unit column on or off, logo on or off), validated by the API. The company logo
   is one PNG, JPEG or SVG of at most 512 KB per company in `core.company_logos`, checked by its
   first bytes (an SVG with scripts, foreignObject or external references is refused) and managed
   by the administrator (`users.admin`) at `/admin/company/logo`. The PDF puts it in the header
   when present and `show_logo` is on (default); the Excel export has no logo.
   A group can be untitled (`show_title` false, `gap_mm` 0 to 50): the title is kept for the
   editor but never printed, and the group's items follow the previous group after the gap.
9. **Where it lives.** The `crates/pricing` crate stays database-free (ADR 0002), so the routes and
   queries are in `crates/products`, next to price zones, in the `products` module. Permissions
   `price_lists.read` and `price_lists.write` belong to that module; `product_manager` and `admin`
   write, `sales` and `viewer` read. Every write is audited as entity `price_list`.

10. **Data model: fully normalised.** No array columns, and no jsonb except `settings`. Every table
    has `company_id`; every child table has a composite foreign key `(parent_id, company_id)` to
    its parent, so a row cannot belong to another company than its parent, and `ON DELETE CASCADE`
    where the parent owns the row (deleting a list removes everything below it).

    | Table | Key | Content |
    |---|---|---|
    | `price_lists` | id, unique (company, code) | code, name, valid_from, `settings` |
    | `price_list_zones` | id, unique (list, zone) | price_zone_id, sort_order |
    | `price_list_zone_languages` | (zone row, language) | sort_order (0 = default), language in nl fr en de es |
    | `price_list_groups` | id, unique (list, id) | parent (same list), sort_order, page_break, show_title, gap_mm |
    | `price_list_group_titles` | (group, language) | title |
    | `price_list_items` | id, unique (list, product) | group (same list), sort_key, four flags |
    | `price_list_item_descriptions` | (item, language) | description |
    | `price_list_exports` | id, unique (list, code), unique (list, id) | name, sort_order, file_name |
    | `price_list_export_groups` | (export, group) | price_list_id, sort_order (profile order) |

    Language codes are `char(2)` with `^[a-z]{2}$` like `products.product_translations` (ADR 0033);
    titles and descriptions are non-empty trimmed text of at most 300 characters. Rules and where
    they are enforced:

    * *A group of an export belongs to the same list as the export*: database. The link carries
      `price_list_id` and has foreign keys `(price_list_id, export_id)` and
      `(price_list_id, group_id)` to the unique `(price_list_id, id)` of both parents.
    * *A used group cannot be deleted*: database (the group side of the link has no `ON DELETE`
      action, so NO ACTION; RESTRICT would also fire when a whole list is deleted, before the
      cascade has removed the links) and API (409 naming the profiles).
    * *Only top-level groups in a profile, and a used group stays top-level*: database triggers
      on the link table and on `parent_id` of groups (a foreign key cannot test `parent_id IS
      NULL`), plus the API check in the same transaction for the 422 and 409 messages.
    * *A zone has at least one language*: database, a deferred constraint trigger (checked at
      commit, so zone and languages can be written in any order in one transaction, and removing
      a zone with its languages is allowed), plus the API validation.
    * *Tree depth (four levels), no cycles, the price zone and product belong to the company*:
      API only, under the list lock. The referenced `price_zones` and `products` tables come
      from earlier migrations and have no `(id, company_id)` key to point a composite foreign key
      at.
    * *The "title in at least one language" rule of a group*: API only (a group row exists before
      its titles do inside the transaction).

    The API shapes are unchanged: titles and descriptions travel as language-to-text maps, zones
    as `{price_zone_id, languages[], ...}`, profiles with `group_ids[]`. Reads rebuild them with
    `jsonb_object_agg` / `jsonb_agg ... ORDER BY sort_order` / `array_agg ... ORDER BY sort_order`;
    every write replaces the child rows as a whole inside the same transaction as the parent
    change, with a deterministic order (`sort_order` for languages and profile chapters).

    `price_lists.settings` stays jsonb on purpose: footer text, currency symbol, accent colour,
    unit column and logo switches are pure presentation options, validated by the API, always
    read and written together with the list, never filtered, joined or referenced by key, and
    new options need no migration. Anything that gets an identity or is queried by key would move
    to a table.

    **Why not jsonb as the configurator does?** The configurator stores a document that is
    edited and read as one unit, and its parts are never
    referenced from elsewhere. Here the parts are referenced: an export must point at groups of
    its own list, a group delete must be blocked by that reference, and a list delete must
    cascade. Arrays and maps cannot carry foreign keys, so those rules would live only in code
    and could be bypassed by any second writer; rows give the database the same guarantees for
    free, make "which profiles use this group" a plain indexed lookup, and keep one text per
    language a checked, keyed value.

**Out of scope.** Price comparison with an older list, increase markers and an uplift tool; the
import of the old sort-order data (planned on the data import framework, ADR 0067); the screens in
the Flutter app (including the bulk export that walks the plan).

**Consequences.** One list prints for every zone and language it is published for, and the plan
tells a client exactly which files that is. A hidden or unpriced product silently does not
appear, which is why the editor must show which items are not printed and why.
