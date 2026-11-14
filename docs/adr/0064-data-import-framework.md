# 0064 — Data import framework: one importer, CSV/XLSX/ODS readers, admin screen, background jobs

**Status:** Accepted (extends [ADR 0029](0029-csv-export-import.md))

**Context.** Customers and products import from CSV (ADR 0029). The entity code in
`crates/crm/src/csv.rs` and `crates/products/src/csv.rs` repeats the same skeleton (handler, plan,
lock, replan, write, audit), so every further entity would copy it again. Onboarding data arrives as
spreadsheets far more often than as CSV, with headers that do not match ours, and in files larger
than one request should carry. This is D10 of the roadmap. This record covers the shared importer,
the spreadsheet formats, the admin screen and background jobs. Parquet and further entities
(contacts, suppliers, stock opening balances, quotations, orders, tickets) follow in their own
changes on the interfaces defined here.

**Decision.**

*Everything ADR 0029 says about semantics stays*: upsert by code, only the columns present are
touched, every row validates first and all errors are collected, any error means nothing is
written, one transaction, one audit event per created or updated record, unchanged rows are neither
written nor audited, nothing is deleted, replanning on a concurrent unique-key conflict. The existing
endpoints, their permissions and their CSV behaviour do not change.

**1. One importer in `core`.** `crates/core/src/import/`:

| Part | Responsibility |
|---|---|
| cell model | `CellValue`: empty, text, number (exact decimal), boolean, date, date-time. The typed accessors (`text`, `trimmed`, `decimal`, `int`, `boolean`) of ADR 0029 read from it. |
| readers | bytes in, one table of typed cells out; format detection; limits |
| `Importable` | what an entity supplies: its columns, its key column, its lookups, how a row becomes a planned change, how equality with the stored record is decided, create and update |
| engine | everything shared: header binding, duplicate keys, `SELECT ... FOR UPDATE` of the named records, classification (create, update, unchanged), dry run, the write loop, audit, replanning, the report |
| writers | a table of typed cells out as CSV, XLSX or ODS |

`crm` and `products` keep only what is theirs (columns, defaults, lookups, row rules, writes) and each
exposes its entity publicly. A registry of the entities is assembled in the new crate
`tradocraft-imports`, which also holds the admin routes and the job runner; the API and the worker
both use it.

**2. Formats.** The format is detected from the bytes, never from the file name or content type: a
zip archive with an OpenDocument spreadsheet `mimetype` is ODS, one with `xl/workbook.xml` is XLSX
(macro-enabled `.xlsm` included), any other zip and the legacy binary formats (`.xls`, `.xlsb`) are
refused with one error, everything else is read as CSV.

*XLSX and ODS* are read with `calamine`:

* The first sheet is used unless `sheet=<name>` names another one; an unknown name is an error that
  lists the sheets. The header is the first row that is not empty; rows that are entirely empty are
  skipped. `row` in an error is the row number in the sheet.
* Values are taken as stored, not as displayed: a number is a number whatever its format, a date is a
  date, a boolean is a boolean. A formula contributes its cached result; a formula without one is an
  empty cell. A cell that holds a spreadsheet error (`#N/A`, `#REF!` ...) is a row error.
* Macros and external links are never evaluated; only cell values are read.
* Before anything is unpacked the archive directory is checked: the sum of the declared uncompressed
  sizes and the number of entries must stay within the limits below, otherwise the file is refused
  with one error (zip bombs). Row and cell limits are enforced while reading.

*Typed cells and fields.* A text field accepts a number cell (a code or postal code typed as `1000`
is the text `1000`, without a trailing `.0`) and a date cell (ISO 8601). A number field accepts a
number cell, or a text cell under the CSV rules (`,` or `.` as decimal mark). A binary float is
converted through its shortest decimal representation, so `7.5` is exactly 7.5; the decimals rules
of the field then apply as for CSV. A boolean field accepts a boolean cell, the numbers 1 and 0, or
the CSV keywords. The whitespace rules of ADR 0029 apply to text cells of every format. The
apostrophe rule for formula characters is a CSV rule only: spreadsheet files store text as text.

*CSV* is unchanged.

**3. Export.** `GET /customers/export` and `GET /products/export` take `format=csv|xlsx|ods`
(default `csv`). The spreadsheet files have one sheet named after the entity, the header row, text
columns as text cells (a code `00123` keeps its zeros, a value that starts with `=` is text, not a
formula), decimals as number cells and booleans as boolean cells. XLSX is written with
`rust_xlsxwriter`; ODS by a small writer of our own on the `zip` crate (one sheet of typed cells does
not justify another dependency tree). An export in any of the three formats imports back as
everything `unchanged`.

**4. Limits.**

| | One request (entity endpoints, admin screen inline) | Background job |
|---|---|---|
| File size | 5 MiB | 50 MiB |
| Data rows | 20 000 | 200 000 |
| Cells per row | 100 | 100 |
| Cells in the sheet | 2 000 000 | 5 000 000 |
| Declared unpacked size of the archive | 64 MiB | 512 MiB |
| Archive entries | 1 000 | 1 000 |

**5. Admin screen** (Administration, tab *Import*). Upload a file, choose the entity and the sheet,
map the file's columns to the entity's fields, dry run, read the report, apply. All of it needs the
new permission `imports.admin` (always on, like `users.admin`; role `admin`) **and** the write
permission of the chosen entity (`customers.write`, `products.write`, ...). The menus on the customer
and product lists keep working with the entity permission alone and now take the three formats.

*Column mapping.* A mapping is a list of `file column → field`. File column names are compared
trimmed and case-insensitively. File columns that are not mapped are ignored; two file columns on
one field, an unknown field, or a missing key column are header errors. Without a mapping the header
must name our columns exactly, as in ADR 0029. The screen proposes the saved mapping whose file
columns all occur in the header, else it pairs equal names. Mappings are saved per company and
entity under a name.

*Tables* (migration `20270206000001_imports.sql`, schema `core`):

| Table | Holds |
|---|---|
| `core.import_files` | an uploaded file: company, file name, detected format, size, the bytes, uploader. Separate from `core.files` (other types, sizes and lifetime). Removed 7 days after upload by the worker. |
| `core.import_mappings` | company, entity, name (unique together), the column pairs, who saved it |
| `core.import_jobs` | one run: company, entity, file, sheet, the column pairs used, `dry_run`, status (`queued`, `running`, `done`, `failed`, `cancelled`), phase, total and processed rows, the counts, the errors (at most 10 000 are kept, with the full count), a failure message, requester, timestamps, attempts, heartbeat |

*Endpoints* under `/imports` (all `imports.admin`):

| Endpoint | Result |
|---|---|
| `GET /imports/entities` | the entities the caller may write, with their columns (name, type, required for a new record) |
| `POST /imports/files?filename=` | raw body; stores the file; returns its id, format and sheets |
| `GET /imports/files/{id}/preview?sheet=` | header columns, row count and the first 20 rows as text |
| `GET /imports/mappings?entity=`, `PUT /imports/mappings`, `DELETE /imports/mappings/{id}` | saved mappings |
| `POST /imports/jobs` | `{ file_id, entity, sheet, columns, dry_run }`. Within the one-request limits the run happens in the request and the finished job is returned (`200`); beyond them the job is queued (`202`) |
| `GET /imports/jobs`, `GET /imports/jobs/{id}` | history and progress |
| `GET /imports/jobs/{id}/errors` | the error report as CSV (`row`, `column`, `message`) |
| `POST /imports/jobs/{id}/cancel` | cancels a job that is still queued |

A run with errors is a finished job (`done`) whose report has errors and zero counts; `failed` is
for a run that could not be carried out (unreadable file, lost permission, worker fault).

**6. Background jobs.** The worker claims the oldest queued job (`FOR UPDATE SKIP LOCKED`), marks it
running and runs the same engine. **All or nothing is kept**: the whole file is validated, then
written in one transaction. The price is that the row locks on the named records are held for the
whole run, which is why a job has a hard cap instead of chunked commits. Progress (phase
`reading`, `validating`, `writing`, and processed rows) and a heartbeat are written on a separate
connection, since the import transaction is not visible until it commits. A dry run of a large file
is a job too; applying it is a second job on the same stored file, which validates again.

The job runs as its requester: the worker loads that user with the roles and modules of the job's
company at run time. If the user is gone or no longer holds `imports.admin` and the entity's write
permission, the job fails and nothing is written. A running job whose heartbeat is older than five
minutes (a worker that died; its transaction rolled back) is queued again. The attempt is counted at
the claim; a stale job that has been claimed three times fails with "the import stopped three
times without finishing". A cancelled job is never claimed.

One worker step covers it, in this order: requeue or fail stale jobs, run queued jobs (at most ten
per pass, each in a task of its own so a panic ends only that run), remove old files. The step runs
in a loop of its own inside the worker process, with the same interval as the main loop and never
two passes at once, so a long import does not delay mail or SLA escalation; the worker heartbeat
(ADR 0052) stays with the main loop. Stopping the process cuts a running import off; the job is
queued again after five minutes.

A file older than 7 days is removed, except when a queued or running job still refers to it. A job
that waited a week for a worker keeps its file and runs; the file goes in a later pass. For a
removed file the job row stays with no file.

**7. Audit.** `data.source` is `csv_import`, `xlsx_import` or `ods_import`. A run through the admin
screen or a job adds `data.import_job` with the job id.

**Alternatives.**

* *Convert every cell to text and reuse the CSV path.* Simple, but a number would be read through its
  display format and a date through the locale of the file: exactly the errors typed cells avoid.
* *Chunked commits for large files.* Shorter locks and no cap, but a failure half-way leaves a
  partial import, which ADR 0029 rules out.
* *Store uploads in `core.files`.* It is sized and typed for images and PDFs shown to users;
  import files are larger, short-lived and never served to anyone but their uploader.
* *A generic job queue.* Only imports need one today; the table is specific and can be generalised
  when a second kind of job appears.
* *The client keeps the file and sends it again for every step.* No server storage for small files,
  but a job needs the file on the server anyway, and two paths would have to be kept alike.

**Consequences.** Three new dependencies (`calamine`, `rust_xlsxwriter`, `zip`). A new entity is one
`Importable` implementation and a registry entry; it gets the formats, the admin screen and jobs for
free. A large import blocks edits to the records it names until it ends. Import files live in the
database for a week, so backups grow by at most the uploads of that week. A spreadsheet whose cells
are stored as text (numbers typed with a leading apostrophe) is read under the CSV rules, so such
files keep working. Parquet needs a reader that yields the same cells in row batches and nothing
else.
