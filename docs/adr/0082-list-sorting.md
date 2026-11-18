# 0082 — Server-side list sorting

**Status:** Accepted (pilot on customers, products and quotations; builds on [ADR 0078](0078-repository-layer.md))

**Context.** Every paged list endpoint hardcodes its `ORDER BY` (customers by name, products by
code, quotations newest first). A list that shows 50 of 2,000 rows cannot be sorted on the client:
sorting the visible page gives a wrong answer. The Flutter list view needs clickable column headers
that ask the server.

**Decision.**

1. **One query parameter.** `sort=field` sorts ascending, `sort=-field` descending. Several keys are
   comma-separated (`sort=-status,name`), at most 3. Absent or blank means the endpoint's current
   default order, unchanged.
2. **A whitelist per endpoint.** `tradocraft_core::sort::order_by(sort, whitelist, tiebreak,
   default)` takes `&[("api_key", "sql_expr")]`. User input is only looked up in that list; it is
   never put in the SQL. The direction is the literal `ASC` or `DESC`. The result is the
   expression list for `ORDER BY {order}`.
3. **Stable paging.** When `sort` is given, the primary key is appended as the last key, so rows
   with equal values keep one order across `limit`/`offset` pages. The defaults are left exactly as
   they were.
4. **NULLs last in both directions.** PostgreSQL sorts NULLs last for `ASC` but first for `DESC`;
   the helper writes `NULLS LAST` on every key so an empty city or email is at the bottom either
   way.
5. **Errors.** An unknown, repeated or empty key, or more than 3 keys, is `AppError::Validation`
   (the standard error body, HTTP 422) naming the allowed keys.
6. **Documented in OpenAPI.** `sort` is a field of each `ListParams` (utoipa `IntoParams`), so
   `api/openapi.json` and the generated Dart list methods carry an optional `sort` argument.
7. **Keys in the pilot.**
   - customers: `code`, `name`, `vat_number`, `email`, `phone`, `city`, `country_code`, `active`
   - products: `code`, `name`, `unit`, `product_type`, `family_code`, `pricing_type`, `active`
   - quotations: `number`, `customer_name`, `status`, `quote_date`, `valid_until`, `subtotal`, `total`

**Consequences.**

- Text keys sort with the database collation, like the existing defaults. Values computed after the
  query (a product's list price for the company) are not sortable.
- Sorting on columns without an index is a sequential sort of the filtered rows; acceptable at
  current volumes, to be revisited with an index when a list grows.
- Follow-up: roll `sort` out to the other paged endpoints (about 9: orders, opportunities,
  favorites and the rest of the `{items,total}` lists). Bare-array endpoints (suppliers,
  purchase orders, admin users, shipping requests) return everything and sort on the client.
