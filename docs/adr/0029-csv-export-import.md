# 0029 — CSV export and import of customers and products

**Status:** Accepted

**Context.** Master data has to be loaded from, and reviewed in, spreadsheets: onboarding a
company, bulk corrections, hand-over to an accountant. Excel in NL/FR/DE locales writes `;` as
delimiter and `,` as decimal mark. A half-applied import is worse than none, so an import must
either apply completely or not at all.

**Decision.** Four endpoints; shared CSV code in `crates/core/src/csv_io.rs`, entity code in
`crates/crm/src/csv.rs` and `crates/products/src/csv.rs`. No migration.

| Endpoint | Permission | Result |
|---|---|---|
| `GET /customers/export`, `GET /products/export` | `customers.read` / `products.read` | `text/csv; charset=utf-8` download, `customers.csv` / `products.csv` |
| `POST /customers/import?dry_run=`, `POST /products/import?dry_run=` | `customers.write` / `products.write` | JSON `ImportReport` |

**Export format.** UTF-8 without byte order mark, `,` delimiter, `.` decimal mark, RFC 4180
quoting, CRLF line ends, header row, ordered by `code`. A text cell that starts with `= + - @` (or a
tab/CR) gets a leading `'` so a spreadsheet cannot run it as a formula. A literal value that starts
with apostrophes followed by such a character (`'=x`) gets one more apostrophe as well (`''=x`), so
the two cases cannot be confused: in the import a cell that starts with `'` and has a formula
character after its leading apostrophes loses exactly that first `'` (`'=x` is `=x`, `''=x` is
`'=x`); every other cell, including `'abc` and a lone `'`, is taken as it is. Booleans are `true`/`false`; decimals have no trailing zeros; empty = null.

**Import format.** The request body is the raw CSV (`Content-Type: text/csv`, no multipart), at
most 5 MB and 20 000 data rows (413 for a larger body). The delimiter (`;` or `,`) is detected from
the header line; a byte order mark is accepted; quoted values may contain delimiters, quotes and
line breaks. Quoting is strict: a quote inside an unquoted value, or any text after a closing quote,
is a format error (line of the record), as is an unclosed quote. The limits (20 000 rows, 100 cells
per record; 400 since ADR 0100) are checked while reading, so an oversized file stops with one error before anything
else is checked. Header names are trimmed and case-insensitive and may come in any order. Unknown or
duplicate columns, a missing `code` column, an empty file or a bad encoding are rejected.

A data row with fewer cells than the header, or with extra cells that are not all empty, is a row
error (`N values but the header has M columns`) and is skipped; the other rows are still checked and
their errors are reported together with these ones, in file order. With any error nothing is written.

Whitespace: free text cells (names, address, description, unit, phone, ...) are kept exactly as
written, including leading and trailing spaces, so an unchanged export is never seen as an update.
An empty cell is blank; a cell of only spaces is a text value, not blank (otherwise a stored value
of spaces could not round-trip). The names the API trims anyway (`code`, `name`) are trimmed. Codes
and keywords (`code`, `price_zone_code`, `family_code`, `packaging_category_code`, `barcode`,
`country_code`, `language`, `product_type`, `tracking`, `pricing_type`) and numbers and booleans are
read without surrounding spaces, and there a cell of only spaces is blank. Decimals accept `,` or
`.` as decimal mark; a value with both (`1.234,5`) is rejected, there are no thousands separators. A
number with more digits than a decimal can hold exactly (more than 28 decimals) is rejected, never
rounded. Booleans accept `true/false/1/0/yes/no/y/n`.

**Semantics.**

* Upsert by `code` (exact match after trimming): an existing code is updated, a new one created. A
  code twice in a file is an error. Nothing is ever deleted; ids of existing rows never change.
* Only columns present in the file are touched. In an update, a blank cell means: for required or
  defaulted fields (everything except the nullable ones below, so also `street`, `postal_code`,
  `city` and `description`) keep the current value; for nullable fields clear them. For a new row a
  blank cell means the default (below). A text field that is not nullable can therefore not be
  emptied through a file.
* Every row is validated first, with the same rules as the create/update endpoints (the shared
  `validate()`, packaging-category and service-conversion checks), plus the lookup of referenced
  codes and the number formats of the database columns. **All** errors are collected. With any
  error the response is `422` and nothing was written. Every independent problem of a row is
  reported (an empty name does not hide a wrong language), and each database-backed check runs
  whenever its own input is usable, so a VAT error and an inactive packaging category show up in
  the same pass. Otherwise everything is written in one
  transaction, with one `audit.events` row per created/updated record (`data.source = "csv_import"`).
  A row whose values equal the stored ones counts as `unchanged` and is not written or audited.
* `dry_run=true` returns the same report, including the 422 on errors, but never writes.

```json
{ "created": 1, "updated": 2, "unchanged": 40, "errors": [] }
```

On `422` the same shape is returned with the counts at 0 and
`errors: [{ "row": 3, "column": "price_zone_code", "message": "..." }]`. `row` is the line in the
file where the record starts (the header is line 1); `column` is null for problems of the whole row.
Header problems are reported the same way, on line 1.

**Customers** (commercial terms are those of the active company). Required for a new customer:
`name` and `price_zone_code`. Required column: `code`.

| Column | Notes | Default for a new row |
|---|---|---|
| `code` | key | |
| `name` | | required |
| `vat_number`, `email`, `phone` | nullable | empty |
| `street`, `postal_code`, `city` | | empty |
| `country_code` | 2 letters, stored upper case | `BE` |
| `language` | `nl fr en de es` | `nl` |
| `active` | boolean | `true` |
| `price_zone_code` | code of a price zone of the active company | required |
| `discount_percent` | -100 to 100 (negative = surcharge), at most 2 decimals | `0` |
| `payment_terms_days` | whole number, not negative | `30` |
| `vat_regime` | `domestic`, `intra_eu` or `outside_eu` (ADR 0038) | `domestic` |

The discount is normalised before the decimals check (`7,500` is 7.5 and accepted; `7,555` is an
error). Terms belong to a price zone: a `discount_percent` or `payment_terms_days` value for a
customer that has none in the active company needs a `price_zone_code` in the same row. A customer
without terms in the active company exports blank terms; importing them back (blank cells) leaves the
customer without terms.

**Products.** Required for a new product: `name` and `vat_rate`. Required column: `code`.

| Column | Notes | Default for a new row |
|---|---|---|
| `code` | key | |
| `name` | | required |
| `description` | | empty |
| `unit` | free text, as in the API | `pcs` |
| `product_type` | `purchased manufactured configurable service` | `purchased` |
| `vat_rate` | not negative, at most 2 decimals | required |
| `tracking` | `none serial lot`; not for services | `none` |
| `family_code` | code of a product family; blank clears | none |
| `pricing_type` | `list net indicative` | `list` |
| `active` | boolean | `true` |
| `reorder_min`, `reorder_max` | not negative, at most 4 decimals, max >= min | none |
| `lead_time_days` | whole number, not negative | none |
| `barcode` | unique across products | none |
| `packaging_category_code` | code of an active packaging category | none |
| `length_mm`, `width_mm`, `height_mm`, `weight_g` | whole numbers > 0 | none |

**Not in the files, on purpose.** The product `standard_cost` (permissioned with `inventory.cost`;
a file passes around many hands) and the zone prices (a dated history with its own permission and
rules, see `/products/{id}/prices` and the bulk price change). Ids, timestamps and anything
computed are never exported or imported. A `standard_cost` column is rejected as unknown.

**Concurrency.** The rows named in the file are read and locked in the same statement
(`SELECT ... FOR UPDATE`). A unique key that a concurrent writer takes between the plan and the
write (a barcode, or a code created at the same moment) cannot be locked beforehand; the failed
attempt is rolled back and the file is planned again (at most three attempts) against the committed
data. The new plan reports a taken barcode as a row error (`422`, never a generic `409`) and turns
the create of a code that now exists into an update.

**Consequences.** A file exported and imported again reports everything `unchanged`; this holds
within the import limits (20 000 rows and 5 MiB), which the export does not have. A larger export
has to be split into several files that each stay within both limits; every file is atomic on its
own, the set of files is not. A product
barcode held by another product is reported as an error even when that product is changed away in
the same file (no barcode swaps). The row errors of rules that need the database are found in the
same pass as the format errors, but the whole check runs in the import transaction, which holds a
row lock on the products/customers named in the file until it ends.
