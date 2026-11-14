# 0042 — User-defined reports (report builder)

**Status:** Accepted

**Context.** the CRM lets users build their own reports: pick an object, choose columns, filter,
group, summarise, chart, save, share and export. tradocraft is meant to replace it, but had only a
fixed helpdesk report (ADR 0021) and entity CSV exports (ADR 0029). Reports must not become a way
around permissions or around the company boundary, and a user-defined definition must never be
able to put text into a query.

**Decision.** A new crate `crates/reports` (module `reports`, permissions `reports.read` and
`reports.write`) and one table, `reports.reports` (`migrations/20270122000001_reports.sql`).

*Definition.* A report is a JSON document stored in `reports.reports.definition`:

| Part | Meaning |
|---|---|
| `object`, `joins` | The object the report is about (`customer`, `quotation`, `order`) and up to two related objects, each linked to one already in the report (customer–quotation, customer–order, quotation–order; left joins) |
| `columns` | `object.field`, optionally with a `summary` (`count`, `sum`, `avg`, `min`, `max`) and a label |
| `filters`, `filter_logic` | Up to 20 conditions (`eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `contains`, `starts_with`, `in`, `is_null`, `not_null`), combined with `and` or `or` |
| `group_by` | Up to 3 fields; date fields can be bucketed by `day`, `month` or `year` |
| `sort` | Up to 5 output columns |
| `chart` | `bar`, `line` or `pie`, with a grouping column for the categories and a numeric summary for the values |

Output columns have keys: a plain column or grouping is `quotation.total`, a bucket is
`quotation.quote_date:month`, a summary is `quotation.total:sum`. `sort` and `chart` refer to these
keys. There are three shapes: plain rows; summaries without grouping (one row); grouped (one row
per group, groupings first, every column a summary, plus a totals line over everything).

*Catalog.* `crates/reports/src/catalog.rs` is the only place where names turn into SQL. Objects,
fields (with type and SQL expression), relations and the `FROM`/`JOIN` fragments are fixed there.
`definition::plan()` checks a definition against it (unknown field, operator not allowed for the
type, a value that does not fit the type, summary not allowed for the type, limits, a field of an
object that is not in the report, chart without a grouping) and returns a `Plan` that the engine
runs without further checks.

*Query.* `engine.rs` builds the query with `sqlx::QueryBuilder`. Every value (the company, filter
values, limit, offset) is a bound parameter; `contains` and `starts_with` escape `\`, `%` and `_`;
sorting uses expressions from the catalog, never text from the request. Rows are selected as
`to_jsonb(...)`, so the response is JSON whatever the column type. Customers are shared master
data and have no `company_id`; their per-company terms (`discount_percent`, `payment_terms_days`)
are joined on the caller's company. Quotations and orders are always filtered on the caller's
company, also when they are joined in.

| Endpoint | Permission | Result |
|---|---|---|
| `GET /custom-reports/catalog` | `reports.read` | The objects the caller may read, their fields, and the possible joins |
| `GET /custom-reports`, `GET /custom-reports/{id}` | `reports.read` | Own reports and the ones shared in the company |
| `POST /custom-reports`, `PUT /custom-reports/{id}` | `reports.write` | Saves; the definition is validated and the author must be able to run it |
| `DELETE /custom-reports/{id}` | `reports.write` | Owner or admin only |
| `POST /custom-reports/run` | `reports.read` | Runs a definition without saving it (the builder's preview) |
| `GET /custom-reports/{id}/run?limit=&offset=` | `reports.read` | `{columns, rows, total, totals, chart}`, pages of at most 500 rows |
| `GET /custom-reports/{id}/export?format=csv\|pdf` | `reports.read` | A file download |

The path is `/custom-reports` because `/reports/profitability` and `/reports/margins` are reserved
for fixed reports (they are guarded by `e2e_stubs.rs`) and `/reports/{id}` would swallow them.

*Permissions.* Running a report also needs the read permission of every object in it
(`customers.read`, `quotations.read`, `orders.read`), checked for the runner and not for the
author, and the module of each object must be enabled for them. The catalog only lists what the
caller may read. A report is private (owner only) or shared with the company; other companies
never see it. A shared report can be run by everyone with `reports.read` but changed only by the
owner or an admin. `sales` and `sales_manager` hold both permissions, `support` and `viewer` only
`reports.read`. Creating, changing and deleting are written to the audit trail (entity `report`).

*Relative dates.* A filter value on a date or date-time field may be an object instead of
`YYYY-MM-DD`: `{"relative": "today"}` and likewise `yesterday`, `this_week`, `last_week` (weeks
start on Monday), `this_month`, `last_month`, `this_quarter`, `last_quarter`, `this_year`,
`last_year`, or `{"relative": "last_n_days", "n": 30}` (30 days up to and including today) and
`{"relative": "next_n_days", "n": 7}` (today and the 6 after), `n` from 1 to 3660. The stored
definition keeps the token, so a saved report stays live; `plan(def, today)` stays pure and
resolves it at each run (run, ad-hoc run, CSV and PDF export; the routes pass
`tradocraft_core::today()`). A token is an inclusive range of days. `eq` matches the whole range
(`ne` everything outside it, NULL included); `gte` and `lt` compare with its first day, `gt` and
`lte` with its last, so `gte last_month` reads "from the start of last month" and `gt last_month`
"after last month". For a single day every operator reads naturally. Date-times compare by UTC
day as before. Relative dates are refused on other field types, with `in`, `is_null` and
`not_null`, for unknown tokens and for `n` outside 1..=3660, all with a 422. Resolved days are
bound parameters like every other value (`Val::Date`, or `Val::Range` for `eq` and `ne` on a
period, written as a parenthesised `>= AND <=`). The PDF shows the token in words and the
resolved range, e.g. "Quote date = the last 30 days (13/10/2026 - 11/11/2026)".

*Paging across midnight.* Tokens resolve per request, so a later page could otherwise resolve a
different range than the first. The run endpoints (`GET /custom-reports/{id}/run`,
`POST /custom-reports/run`) and the export take an optional `as_of` (`YYYY-MM-DD`; query
parameter, or body field for the ad-hoc run). It replaces today for that request; absent, the
route uses `today()`. Every `ReportRunResult` returns the `as_of` it used and the Flutter screen
sends the first page's value with every later page, and the CSV and PDF export buttons send the
value of the result on screen (none before a result exists), so rows, totals, chart and files come
from one range.
A fresh run (reload, edit) sends none. Bounds: not older than 366 days and not more than 1 day
ahead of today (clients ahead of UTC); anything else, or a malformed date, is a 422. `plan()` stays
pure and records the day in `Plan::as_of`.
The routes read today from an optional `ReportClock` request extension (default `today()`), which
tests set to exercise a real midnight and month-end rollover without global state.

*Export.* CSV uses `csv_io::write_csv` and `download` (ADR 0029): formula protection, CRLF, the
numbers without trailing zeros, the totals line last, at most `MAX_ROWS` (20 000) rows, a 422 above
that. PDF is rendered with Typst (`templates/report.typ`, data from `crates/reports/src/pdf.rs`) in
the company's default language, with Belgian number and date notation, the filters in words, the
chart and the table with a repeating header; wide reports turn landscape. A PDF has at most 2 000
rows (422 above that, the CSV has no such limit).

**Consequences.**

* Field and object labels in the catalog, and the default column headings, are English; a column
  can be given its own label. The labels of the interface around them are translated (nl, fr, en,
  de, es).
* Numbers travel as JSON numbers, so amounts above about 9 × 10¹⁵ would lose digits. Money in the
  database is `numeric(18,2)`; the totals of a realistic company are far below that.
* The PDF draws every chart as horizontal bars (a pie also shows each share, a line is drawn as
  bars); the app draws a real line chart.
* Date-time filters compare by UTC day.
* Adding an object (products, tickets, ...) means: a catalog entry with its permission, a `FROM`
  and `JOIN` fragment, the links, and a test that it stays inside the company. Nothing else changes.
* Scheduled report e-mails were added in ADR 0065. Not done: dashboards, report folders and
  sharing with single roles and multi-level sorting of groups.
