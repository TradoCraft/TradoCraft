# 0021 — Helpdesk: business hours, automation rules, ticket split and reporting

**Status:** Accepted

**Context.** ADR 0017 left four gaps open: the SLA ran around the clock, there was no way to let the
system sort tickets, one e-mail with two topics stayed one ticket, and nobody could see how the
helpdesk was doing. They are closed together because they touch the same code paths: the SLA
columns, the ticket create/update/reply paths and e-mail ingest.

**Decision.**

### Business hours (SLA)
* **One calendar per company, optionally one per team** (`helpdesk.business_calendars`,
  `business_hours`, `holidays`): a time zone (IANA name, default `Europe/Brussels`), at most one
  opening interval per ISO weekday, and holidays (date + name). A company without a calendar, or
  with `enabled = false`, keeps plain elapsed time: nothing about the old behaviour changed.
  Settings are kept when the calendar is switched off.
* **Business time** runs only inside the opening interval of a working day that is not a holiday.
  The arithmetic is pure and unit tested in `sla.rs`: `Calendar::add_business_seconds` (the instant
  at which N business seconds have passed; a start outside hours begins counting at the next
  opening; landing exactly on closing time stays on that day) and
  `Calendar::business_seconds_between`. Opening times are local wall-clock times converted per day,
  so a 09:00 opening is 08:00 UTC in winter and 07:00 UTC in summer; on the day the clock jumps
  forward a time that does not exist is read with the offset from before the jump, on the day it
  jumps back the first of the two instants is the opening and the second the closing time. A calendar
  without any working day is treated as no calendar.
* **Due times** are still stored on the ticket and still equal *creation + window + time spent
  waiting for the customer*, but with a calendar the window and the waiting time are business
  seconds (`sla::due_in`). "At risk" (less than 25 % of the window left) and `minutes_remaining`
  are measured in business time too (`target_state_in`).
* **Pauses are kept as intervals** (`helpdesk.sla_pauses`, one row per time the status was
  `pending_customer`), so that a change of the calendar can recompute any ticket exactly: a pause
  from Friday 16:00 to Monday 10:00 costs two business hours, not 66. The old columns
  (`sla_paused_at`, `sla_paused_seconds`) stay and keep driving elapsed mode and the worker. Pauses
  recorded before this migration only have their total in `sla_paused_seconds`; that part is taken
  as it is (as business seconds with a calendar). An open pause is migrated into a row.
* **Risk instants** `first_response_risk_at` and `resolution_risk_at` are stored next to the due times
  (the moment 75 % of the window is used) so that the SQL filter `sla=at_risk` needs no calendar. The
  Rust evaluation and the SQL filter agree by construction (both derive from the same `sync`).
* **Recompute.** Saving the calendar, adding or removing a holiday recomputes the open, non-internal
  tickets it concerns (see per-team calendars) through `sla::sync` (the mechanism policy edits already use) in the same transaction.
  Closed tickets keep what they had. Enabling the calendar can make open tickets breach at once.
* **Admin API** (permission `helpdesk.admin`): `GET/PUT /helpdesk/calendar`,
  `POST /helpdesk/calendar/holidays`, `DELETE /helpdesk/calendar/holidays/{id}`.

### Per-team calendars
* The three calendar tables have a nullable `team_id` (null = the company calendar); uniqueness
  is per `(company_id, team_id[, weekday | day])` (`UNIQUE NULLS NOT DISTINCT`).
* **Which calendar applies** to a ticket is decided by its team (`calendar::load_calendar(conn,
  company, team)`): the team's own calendar if it has one, else the company's. A team calendar
  that is switched off means plain elapsed time for that team (it does not fall back).
  **Holidays** of a team with its own calendar are its own holidays plus the company's: a team
  can add days off but never works on a company holiday. A team cannot hold
  holidays before it has a calendar of its own (422). Removing the team calendar
  (`DELETE /helpdesk/calendar?team_id=`) removes its holidays too and hands the team back to the
  company calendar.
* `sla::sync` selects the ticket's team, so due times follow it. It runs again when the team
  changes: staff assignment (`PUT /tickets/{id}/assignment`) and the automation action
  `set_team`. Creation paths (default team) already synchronise after the team is set; merge,
  split (copies the team) and escalation do not change a ticket's team.
* **Admin API**: `GET/PUT /helpdesk/calendar` and `POST /helpdesk/calendar/holidays` take an
  optional `team_id` (404 for a team of another company); `DELETE /helpdesk/calendar?team_id=`
  is new. The calendar answer says `team_id`, `inherited` (the team has no calendar of its own,
  what is shown is the company's) and `holidays_inherited` (set for a team: the company holidays
  count for it as well as the holidays listed).
* **Recompute is scoped** to the open, non-internal tickets the edit can change: a team edit
  recomputes the tickets of that team; a company hours/zone/switch edit those without a team and
  of teams without a calendar; a company holiday edit every open ticket, because a team observes
  the company holidays as well as its own.
* **Reports** load a calendar per ticket team (cached per request). Days still follow the company
  calendar's time zone. `basis` is `business`, `elapsed` or `mixed` (some measured tickets have a
  calendar, others not).
* **Flutter**: the business hours page has a team selector (whole company, or a team); an
  inherited team shows a notice, *Use the company calendar* removes the team's own calendar.

### Automation rules
* **Table** `helpdesk.automation_rules` per company: name, `active`, `position`, `trigger`
  (`created` | `updated` | `customer_replied`), `conditions` and `actions` as JSON, `stop_on_match`.
* **Conditions** (all given ones must hold; a list holds when the ticket has any of its values):
  priority, category, status, customer, customer language, channel, subject contains, sender
  domain, tag, team, owner empty/set. Tickets got a `channel` (`email | portal | phone | manual |
  internal`), set where they are created and derived for existing ones.
* **Actions**: set owner, set team, set priority, set category, add tag, set internal flag. A flat
  `{kind, user_id, team_id, value, flag}` object keeps the OpenAPI shape generator-friendly. No
  e-mail and no scripting.
* **Evaluation** is the pure function `automation::evaluate`: rules run in order of position, each
  once; the changes of a rule are visible to the rules after it; a rule with `stop_on_match` ends the
  run. All matching rules apply otherwise (the last one has the last word on a field). Actions that
  would change nothing are not changes and are not audited.
* **Where it runs**, inside the transaction of the operation: ticket creation (staff, phone call,
  production question, portal, e-mail ingest, split), staff updates (`PUT /tickets/{id}`,
  assignment, replies, notes that change the status), and customer replies (e-mail ingest on an
  existing ticket, portal message, incoming call).
* **Loop guard.** The changes are written directly and never raise a new event, and each rule is looked
  at once per event, so a rule can neither re-trigger itself nor another rule; two rules that undo
  each other simply both run once per event. A priority or internal change re-syncs the SLA.
* **Audit.** Every applied change writes `audit.events` (`automation_rule_applied`) on the ticket with
  the rule id and name, the trigger and the change. They are system events without a user (the
  staff action that caused the run has its own event).
* **Endpoints** (`helpdesk.admin`): `GET/POST /helpdesk/automation/rules`,
  `PUT/DELETE /helpdesk/automation/rules/{id}`, `PUT /helpdesk/automation/order` (must list every
  rule once) and `POST /helpdesk/automation/dry-run {ticket_id, trigger}`, which returns for each
  rule whether it would apply (`matched`, `no_match`, `inactive`, `other_trigger`, `after_stop`) and
  its changes, and changes nothing. Owners and teams named in a rule must belong to the company; a
  rule whose owner left the company is skipped for that change.

### Ticket split
`POST /tickets/{id}/split {article_ids, subject?}` (permission `helpdesk.write`) moves the selected
articles, with their attachments, to a new open ticket with the same customer, contact, language,
category, priority, links, team and owner. The subject is the given one, else the first moved message's,
else the source's. The new ticket gets its own number, its SLA starts at its creation (it has no first
response yet), the creation rules run, and both tickets get a system note naming the other and an audit
event `split`. Moving every message is refused (at least one must stay in the source, so the source is never
empty); a merged ticket cannot be split; messages that are not in the ticket are
a 422. It cannot be undone, but tickets can be merged again. The source keeps its first-response time.
Tags and time entries stay with the source. Mail that answers a moved message is threaded into the new
ticket by its message id.

### Reporting
`GET /helpdesk/reports` (permission `helpdesk.read`) with `from`, `to` (default the last 30 days, at
most 731 days), `team_id`, `owner_id`, `category` and `group` (`day` | `week`, weeks start on Monday)
returns: tickets created and closed per bucket (empty buckets included); the open backlog by status,
priority, team and owner (not limited by date); first-response and resolution time, average and 90th
percentile (nearest rank) in minutes; SLA compliance (tickets created in the period that did not
breach, as a percentage) and breaches per team; CSAT responses, good and bad, and the share of good
ratings; the ten most used categories and tags; and logged time by user and billable or not.
* Counts are SQL aggregates in `crates/helpdesk/src/reports.rs`, all filtered by `company_id`. Merged
  tickets are left out; internal tickets are in the volume and backlog but not in the SLA and time
  figures.
* **Days are the company's local days** (the calendar's time zone, else UTC).
* **Response and resolution times** are computed in Rust over the rows (they need the calendar): with
  an enabled calendar in business time, otherwise elapsed time, minus the pauses inside the span
  (`basis` says which). Resolution counts closed tickets only.
* **CSV**: `GET /helpdesk/reports/export?table=…` with the same filters returns one table (`volume`,
  `backlog_status`, `backlog_priority`, `backlog_team`, `backlog_owner`, `times`, `sla`,
  `breaches_by_team`, `top_categories`, `top_tags`, `time_by_user`) as `text/csv`, comma separated,
  CRLF lines. Cells that start with `= + - @` are prefixed with an apostrophe so a spreadsheet does not
  run them. Dates in the query may be sent as date-times (the generated client does).

### Flutter
Settings link to *Business hours* (week with opening times, time zone, holidays) and *Automation
rules* (list with summary, up/down, switch, edit, delete, dry run, editor). The ticket screen has
*Split ticket…* (choose messages) when there are at least two. The ticket list has *Reports*: key
figures, a created/closed chart and bar lists drawn with `CustomPaint` and plain widgets (no charting
package), filters, and *Copy as CSV* for every table (the app puts the CSV on the clipboard).

**Consequences.**
* Enabling the calendar recomputes all open tickets; some may be breached the moment it is saved.
* Rules run on every ticket event of their trigger, in the request's transaction; many rules add a
  little work to each ticket save.
* A pause that was recorded only as a total (before the migration) cannot be re-measured in business
  time.
* A ticket's `channel` is fixed at creation; tickets that existed before the migration got theirs
  from their first message.
* Reports of long periods read all tickets of the period into memory for the time figures; fine for the
  size of the company, to be revisited past tens of thousands of tickets in a period.

**Not yet.** A calendar per customer, macros in rules (e-mail actions, scheduled report mails and
SLA notices to the customer came with ADR 0064 to 0066), saved report views, a file download instead of the
clipboard for CSV, reports on knowledge base use, and moving the tags/time entries along with a split.
