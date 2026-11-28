# 0100 — Import of product translations, zone prices and price list items; fixed values in a mapping

**Status:** Accepted (extends [ADR 0067](0067-data-import-framework.md))

**Context.** Moving a catalogue from another system means more than products: their names in other
languages, the zone prices with their start dates and the printable price lists (ADR 0074) with
their group tree. Typing that into the editors is not realistic for thousands of rows, and the
exports of other systems rarely have one column for every field: a start date or the target list is
often the same for the whole file. How a price list is laid out differs from one company to the
next, so nothing about it may be a rule of the importer.

**Decision.** Everything of ADR 0029 and ADR 0067 stays: upsert on the key, only the columns of
the file are touched, all or nothing, dry run, report, one audit event per written record, nothing
deleted, the admin screen and background jobs.

**1. Framework extensions (generic).**

* *Keys of several columns.* `Importable::KEY_COLUMNS` (default: the one `KEY_COLUMN`) lists the
  columns that together identify a record. The engine encodes their trimmed values into one key
  for `load` and `plan_row` (`composite_key`: a JSON array of the values, so a code may hold any
  character without two keys becoming equal; a key of one column stays the plain value), requires
  every one of them in the file and reports a duplicate key with all its parts
  (`P-100 / Z1 / 2027-01-01`). `ImportDescription` gains `key_columns`;
  `key_column` stays (the first one) so existing clients keep working.
* *Audit per entity.* `Importable::audit_event` decides the audit event of a written record. The
  default is the `created`/`updated` event of ADR 0067; an entity whose manual edits are audited on
  another record says so (a zone price on its product, an item on its list).
* *Per-language column families.* A `Column` can be `per_language`: `name` stands for `name_nl`,
  `name_fr`, `name_it`, ... A file may have any number of them; the suffix must be an ISO 639-1
  code, checked against the full list in `tradocraft_core::language` (`ns` or `xx` are unknown
  columns, not new languages). Binding and mapping validation accept the family members; the entity
  finds the languages of a file among the bound columns. An export writes one column per language
  that occurs in the exported data, sorted by code; a text stored under a code that is not ISO
  639-1 (the tables accept any two letters) is left out of the export, so an export never has a
  column its import would refuse, and an import never touches such a text.
* *Cells per row.* An export must read back, and the widest one, the products file, has 25
  columns plus a name and a description for each of the 184 ISO 639-1 codes (393). The limit of
  cells per row of ADR 0029/0067 is therefore 400 instead of 100, for one request and for a job;
  the other limits (rows, cells in the sheet, sizes) are unchanged. The import is therefore not limited to the
  languages the application offers elsewhere; the database keeps whatever constraints it has
  (`products.product_translations` and `pricing.price_list_group_titles` take any two lowercase
  letters).
* *Exports carry their header* (`ExportTable`): it depends on the data once families exist.
  `GET /imports/entities/{key}/export?format=csv|xlsx|ods` exports any registered entity in the
  columns of its import; it needs `imports.admin` and the entity's read permission.

**2. Product translations** in the products file: `name_<code>` and `description_<code>`, read
from and written to `products.product_translations`.

| Row says, for one language | Result |
|---|---|
| a name (not blank) | the name is set; the description is the description cell, or the stored one when that column is not in the file (empty for a new translation) |
| no name, a description | the stored translation gets the description; without one, the product's own name becomes the translation's name (a translation needs a name, and an error would make a description-only file useless) |
| neither (blank or absent) | unchanged: an import never deletes a translation |

Unchanged detection includes the translations, so an export imports back as unchanged.

**3. Zone prices** (`zone_prices`, permission `prices.write`, read `products.read`): one row per
product, zone and start date; key `product_code`, `zone` (a price zone code of the company),
`valid_from` (`YYYY-MM-DD`; a date cell of a spreadsheet is read that way); `unit_price` with at
most four decimals. The rules of the price endpoints apply: a new dated price can start on any
date; the price of an entry in effect (`valid_from` today or earlier) is history and is not changed
(a row error tells to add a new date instead); a planned price can be corrected. The audit events
are those of the endpoints (`price_added`, `price_corrected` on the product). The import never
applies the default multiplier or rounding of a zone. The export holds the whole history.

**4. Price list items** (`price_list_items`, permissions `price_lists.write` / `price_lists.read`):
key `price_list` (a list code of the company) and `product_code`; `position`, the title family
`group_title_<code>` and the item flags `price_on_request`, `net`, `indicative`, `hidden`. Item
descriptions are not part of the file.

A position is a dotted string. Spaces and dots at either end are dropped (`"3."` is `3`); an empty
segment in between is an error. The first *N* segments are the group path, each a whole number
that is the `sort_order` of a group among its siblings; groups that do not exist are created along
the path. The rest is the item's sort key (letters and digits, as in the editor). The title cells
of a row belong to the deepest group of its path; empty cells are ignored. A group created without
any title in the file is untitled (`show_title` false, no title text): it prints no heading, and the
editor asks for a title when the group is next edited, as it does for every group. Two existing
siblings at the same `sort_order` make the path ambiguous: a row error that asks to fix the tree in
the editor first. Rows without a position keep their item where it is (a new item needs one).

How a list reads the file is a **setting of the list** (`settings`, validated by the API, defaults
in brackets), because companies lay out their lists differently:

| Setting | Values |
|---|---|
| `import_group_levels` | *N*, 1 to 4 (the tree depth) [2] |
| `import_title_conflict` | which title a group gets when its rows disagree in a language: `lowest_position` (the row with the lowest position, compared segment by segment like sort keys) [default], `first_row` (the first row of the file), `error` (every disagreeing row is an error) |
| `import_short_position` | a position with fewer than *N* segments: `shallower_group` (the item goes into the group it names, with an empty sort key) [default] or `error` |

The export writes the group path and the sort key as the position and the titles of the item's
group. It imports back as unchanged when the tree matches the setting; an item that a position of
*N* group levels cannot express (its group is deeper than *N*, or shallower with a sort key) is
written as it is and would be read differently: change the setting or the tree before re-importing
such a list. A list's lock (`FOR UPDATE`, like the editor) serialises the import with edits of its
tree. Audit events are those of the editor (`item_added`, `item_updated` on the list).

**5. Fixed values in a mapping.** A pair of a mapping is `{ "column": ..., "field": ... }` or
`{ "value": ..., "field": ... }`: exactly one of the two. A value fills the field in every row and
is read like a text cell of the file (so `12,50` is a decimal, `2027-01-01` a date). It may not be
blank or longer than 1 000 characters, and a field cannot be both a file column and fixed. Saved
mappings, jobs and `POST /imports/jobs` take both shapes; stored mappings of the old shape read as
before, so no migration is needed. The admin screen offers "fixed value" next to the file columns.

**Alternatives.**

* *Hard-coded position rules* (two group levels, the lowest position wins): simplest, but another
  company's file would not fit. Settings with neutral defaults cost three fields.
* *The settings on the mapping instead of the list.* A list is laid out one way, whatever file
  feeds it; keeping it on the list also lets the editor show it.
* *A fixed list of languages for the columns.* It would tie the import to the languages the rest of
  the application offers today; a family checked against ISO 639-1 does not.
* *Deleting translations or items that are not in the file.* Against ADR 0029: an import never
  deletes.

**Consequences.** Two more entities in the registry; the products file gains translation columns
(an export now holds them, and old files without them keep working). Clients of
`GET /imports/entities` see `key_columns` and `per_language`; old clients keep working with
`key_column`.
