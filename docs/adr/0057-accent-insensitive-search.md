# 0057 — Accent-insensitive search

**Status:** Accepted

**Context.** The list searches compared `lower(column) LIKE '%text%'`, so "Liege" did not find "Liège",
"Koln" not "Köln", "Werkstrasse" not "Werkstraße". In a company that works in Dutch, French, German,
Spanish and English, names are typed with and without accents all day (a keyboard without the key, a
caller spelling a name, an order form). Suppliers were worse off: the API returned the whole list and
the app filtered it in Dart with `toLowerCase().contains`. Roadmap item D5.

**Decision.** One rule, applied by the database to the column and to the search text alike: lower
case, then strip accents with PostgreSQL's `unaccent`.

*The fold.* `core.search_fold(text)` is `lower(unaccent(text))`, `IMMUTABLE`, `STRICT` (NULL stays
NULL, so a missing value never matches). `unaccent()` itself is only `STABLE` because its rules can be
replaced, which an index cannot accept; the wrapper pins the dictionary by name (`public.unaccent`)
and promises it does not change. If the rules are ever replaced, the indexes below must be rebuilt
(`REINDEX`). It covers what the five languages need: `é è ê ë ç à â î ï ô û ü ö ä ñ á í ó ú`, `ß` to
`ss`, `œ` to `oe`, `æ` to `ae`, `ł` and `å` (the test pins these). Both extensions (`unaccent`,
`pg_trgm`) are *trusted* since PostgreSQL 13: the owner of the database creates them, no superuser.

*Prerequisite.* The function and the indexes name the schema `public`, so the extensions must live
there. On a database where `unaccent` or `pg_trgm` is already installed in another schema, `CREATE
EXTENSION IF NOT EXISTS` changes nothing, so the migration checks first and stops with the way out
(`ALTER EXTENSION <name> SET SCHEMA public`, as the extension's owner) instead of failing later with
"function public.unaccent does not exist".

*The query.* `core::search` has two helpers. `pattern(q)` trims, treats the user's `%`, `_` and `\`
as the characters they are (a search for `100%` finds "Rabat 100% BV", not everything) and wraps
the text in `%`; a blank search is no filter. `matches(expr, param)` is the SQL test
`core.search_fold(expr) LIKE core.search_fold(param) ESCAPE '\'`. Folding happens in SQL on both
sides, so the rules cannot drift between a Rust copy and the database, and the indexes always match.

*Where.* Customers (code, name, VAT number, city), contacts ("first last", "last first", and the
customer's name, in the "who is calling" lookup), products (code, name) and suppliers (name, code,
e-mail, contact person). Suppliers gain a `q` parameter on `GET /suppliers`; the app's supplier list
now passes the search to the server instead of filtering in Dart, and keeps paging on the client
because the list stays small.

*Indexes.* Trigram GIN indexes on the folded expressions for customers (4), contacts (2) and products
(2), so `LIKE '%text%'` does not read the table. A search ORs several columns, and the planner only
uses the indexes when every one of them has one, which is why every searched column has its own.
Suppliers are per company and stay in the hundreds: no index.

*Checked on 200,000 customers.* The plan is a `BitmapOr` over the four indexes: 10 ms against 66 ms
for the old `lower() LIKE` sequential scan. At the sizes a company of 20-50 users has (thousands of
rows) the planner will choose a sequential scan, which is just as fast; the indexes are for growth.
The migration also applies as the owner of a database who is not a superuser, and
`pg_dump | pg_restore --exit-on-error` (the environment clone, ADR 0048) restores the extensions,
the function and the indexes.

**Alternatives.**
- *Folding in Rust and comparing with `lower(column)`.* The column side would still be unfolded, so
  accents in the stored value ("Liège" searched as "liege") would not match. Storing a folded copy of
  every searched column adds columns to keep in step. The function on both sides needs neither.
- *A generated search column per table.* One column and one index per table instead of several, but
  it changes four tables' shapes and the definition lives in each table. The expression indexes
  leave the tables alone.
- *ICU nondeterministic collations (`CREATE COLLATION ... deterministic = false`).* They give
  accent-insensitive equality but not `LIKE '%text%'`, which PostgreSQL does not support on them.
- *`ILIKE` only.* That is what D5 replaces: case-insensitive, still accent-sensitive.
- *Full-text search (`tsvector`).* Right for prose (the knowledge base uses it, ADR 0018); wrong for
  a name typed in part, where users expect a substring.

**Consequences.**
- Every other list that searches with `lower(...) LIKE` still does (orders and quotations by customer
  name, tickets, repairs, packages, delivery notes, field jobs, contracts, stock, production orders,
  finance invoices, report filters). Each is a one-line change to `search::matches`; they were left
  out so that D5 stays reviewable. Until then, a customer found by "Liege" in the customer list is not
  found by that text in the order list.
- Sorting is untouched: `ORDER BY name` still follows the database collation.
- A new list with a text search should use `core::search`, and a column that is searched on large
  tables needs a matching index (the expression must equal the one in the query).
- The default plan after the statement cache switches to a generic plan (after five runs) cannot use
  the indexes, because the `($n IS NULL OR ...)` shape hides the pattern from the planner. PostgreSQL
  only switches when the generic plan's estimated cost is no higher than the average of the custom
  ones, which a sequential scan is not once an index exists, so the custom plans stay. This is how every list in the code base
  is written.
