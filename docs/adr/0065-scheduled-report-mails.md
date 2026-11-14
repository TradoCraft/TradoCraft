# 0065 — Scheduled report mails

**Status:** Accepted

**Context.** Managers want the weekly helpdesk figures or a saved report (ADR 0042) in their inbox without
opening the app. Both ADR 0021 and ADR 0042 listed "scheduled report mails" as a gap. Two kinds of report
exist: a saved definition of the report builder, and the fixed helpdesk report whose parameters are
query parameters (there are no saved helpdesk views). Mailing data is also the one place where a report
leaves the application, possibly to an outside address, so it must not become a way around permissions.

**Decision.**

* **One scheduler, one table**: `reports.schedules` (`company_id`, `owner_id`, `source` `custom` |
  `helpdesk`, `report_id` or a `helpdesk` JSON spec, `frequency` `daily` | `weekly` | `monthly`,
  `weekday` 1 to 7 or `day_of_month` 1 to 28, `send_time`, `time_zone` (IANA, default `Europe/Brussels`),
  `format` `csv` | `pdf`, `user_ids`, `addresses`, `active`, `next_run_at`, `last_run_at`, `last_status`
  `sent` | `failed`, `last_error`). Check constraints keep the shape consistent (a weekly schedule has a
  weekday and no day of the month, and so on). Deleting a saved report deletes its schedules.
* **Helpdesk source.** `{table, period, team_id?, owner_id?, category?, group?}`: `table` is one of the CSV
  tables of ADR 0021, `period` is relative, so the schedule stays current: `yesterday`, `last_7_days`,
  `last_week` (Monday to Sunday before today), `last_30_days`, `last_month` (the previous calendar month),
  counted in the schedule's time zone. The tables come from the same `helpdesk::reports::build` as the
  screen (`reports::table` now returns a `Table` that renders to CSV; the CSV output is unchanged).
* **Timing** is pure (`schedule::next_run`, unit tested): the next local wall-clock time after a given
  instant that matches the frequency, so 07:00 stays 07:00 across the daylight saving change (a time
  that does not exist is read an hour later, of two the first). Days of the month stop at 28 so every month
  has one. The next run is computed from the moment of the run, not from the previous due time: a worker
  that was down for days sends **one** mail when it returns, not one per missed day.
* **Worker pass** `schedule::run_due` (every pass, 30 s by default, before the outbox is emptied): up to 20
  due schedules, each claimed with `FOR UPDATE SKIP LOCKED` in its own transaction, so several workers
  never run one twice. In that transaction the file is built, one mail per recipient is queued in
  `core.mail_outbox` with the file attached (`enqueue_with_attachment`), and `next_run_at`,
  `last_run_at`, `last_status` are written. A crash before the commit repeats the run, never half of it.
  The outbox loop sends the mail, or writes a file outside a live environment (ADR 0048), so the
  environment switch-off applies. The worker renders PDF with `TYPST_BIN` and `TEMPLATE_DIR` like the API
  (set in the Docker image).
* **Permissions.** A new permission **`reports.schedule`** (admin and sales manager) is needed for every
  endpoint, because the feature sends company data out of the application, possibly outside the company. To
  create or change a schedule the person must also be able to run the report themselves: `reports.read` and
  the read permission of every object in a saved report, and it must be their own or a shared report
  (otherwise 404); `helpdesk.read` for the helpdesk source. **A run uses the owner's permissions at the
  moment it runs**: the owner is loaded again from `core.user_companies` (active, roles, disabled modules),
  and a person who left, was deactivated or lost a permission turns the run into a recorded refusal. The
  report builder's rules (company scoping, whitelisted catalog, bound parameters) are those of ADR 0042
  because the same `plan` and `engine` run.
* **Recipients.** Colleagues (`user_ids`, active members of the company when the schedule is saved *and*
  when it runs; they get the mail in their own language) and fixed addresses (validated, lower-cased, in the
  company's default language). At least one, at most 50. A mail per recipient, so addresses are not exposed
  to each other.
* **Failures.** A refusal (the owner lost access, the report was deleted, more rows than the export limit,
  PDF over 2 000 rows, Typst failed) queues nothing, is stored as `last_status = failed` with the reason,
  audited, and the schedule moves on to its next time: it is **not** retried every pass and not
  switched off. Database errors are not recorded; the transaction rolls back and the next pass retries.
  There is no failure mail; the app shows the reason on the schedule.
* **Endpoints** (tag `reports`): `GET/POST /report-schedules`, `PUT/DELETE /report-schedules/{id}`, and
  `POST /report-schedules/{id}/send` (builds and queues the mail now, with the owner's permissions, without
  moving the next run; a refusal is a 422 with the reason). Only the owner or an admin changes, deletes or
  sends a schedule; an admin who saves somebody else's schedule becomes its owner, because the save checks
  *their* permissions and the run uses the owner's. Create, update, delete (user) and each run (system
  event `run`, with counts and the error text, never addresses) are audited.
* **Flutter.** *Scheduled mails* page (`/reports/schedules`, linked from the saved reports and the helpdesk
  report page for people with `reports.schedule`): list with when, format, recipients, next and last run (the
  failure reason), pause switch, send now, edit, delete, and an editor with a saved-report or helpdesk
  source, frequency, weekday or day, time, format, colleagues and addresses.

**Consequences.**
* The file is built once per run and attached to every recipient's mail (kept in the outbox row as `bytea`
  like other system mail attachments, ADR 0048): large PDFs times many recipients cost database space until
  the mail is sent. Limits keep it bounded (20 000 CSV rows, 2 000 PDF rows, 50 recipients).
* The helpdesk PDF is a plain table (header, rows) under a title and the period; there is no chart. Column
  headings and table names are the English keys of the CSV export, as in the screen's CSV.
* A saved report's relative dates resolve on the day of the run in the schedule's time zone.
* A schedule whose owner permanently lost access keeps failing, visibly, until somebody changes or deletes it.
* Time zone and daylight saving: a schedule is in one fixed IANA zone, not the viewer's.

**Not yet.** Per-recipient permission checks (the file is built with the owner's rights and every
recipient gets it), failure mails and automatic pausing after repeated failures, quarterly or custom
cron-like timing, several reports in one mail, report folders and dashboards, and mail templates (A6).
