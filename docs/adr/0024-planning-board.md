# 0024 — Planning board for field jobs: calendars, skills, conflicts, suggestions

**Status:** Accepted

**Context.** Field jobs (ADR 0015, 0020) could be assigned and given an appointment on the job
form, one job at a time and blind: nothing showed who was free, on holiday, outside their hours
or lacked the skill, and a double booking was only noticed on the day. The roadmap item C3 asks
for one planning board for field jobs and, later, work centres. This ADR is the field-jobs half;
the work-centre half (capacity, finite loading) is still open.

**Decision.** New crate `crates/planning` (schema `planning`), migration
`20261114000001_planning_board.sql`, tag `planning` in the API. Every table carries `company_id`
and every query filters on it (another company gets "not found" or empty lists).

* **Resource calendar** (reusable by work centres): `planning.working_hours` (weekday 1-7, start,
  end; several rows per day allowed, e.g. morning and afternoon; `user_id` NULL = company default,
  used for every user with no rows of their own), `planning.absences` (inclusive date range, kind
  `vacation|sick|training|other`, note), `planning.settings` (per company: travel buffer,
  default job length, time zone). They are keyed by user today; work centres will add a sibling
  resource column with a CHECK that exactly one is set. The pure functions already work on a
  generic `ResourceCalendar` (id, hours, absences, skills, booked blocks).
* **Skills**: catalogue `planning.skills` (code unique per company, name), `planning.user_skills`
  (level 1-3) and `field.job_required_skills` (job, skill; in the planning migration but keyed to
  `field.jobs`). Deleting a skill removes it from users and jobs.
* **Travel time is a buffer, not routing.** `planning.settings.travel_buffer_minutes` (default
  15) is kept free between two consecutive jobs of a technician **that touch the same calendar
  day**; it does not reach across days. No external routing API, no coordinates, no home
  address (`user_home` was left out): the buffer is the same whatever the distance.
* **Time zone.** Working hours and absences are local; job times are instants.
  `planning.settings.timezone` (default `Europe/Brussels`, validated against `pg_timezone_names`)
  says which zone the calendar is in. The conversion is done by Postgres (`AT TIME ZONE`) so the
  Rust side stays pure on naive local times and needs no time zone crate.
* **Permissions** `planning.read` (see the board, suggestions, skills, settings),
  `planning.write` (schedule and assign, record absences, set a job's required skills),
  `planning.admin` (working hours, skills catalogue, technicians' skills, settings). Roles:
  `admin` everything; `sales_manager` and `dispatcher` read and write; `viewer` read. A
  technician has none of them but may read their own absences, working hours and skills
  (`user_id` = themselves), and still sees only their own jobs elsewhere. Technicians on the board
  are the active users of the company with the role `technician`.
* **Endpoints.** `GET /planning/board?from&to` (period of at most 62 days; technicians with
  skills, effective working hours and absences; assigned jobs of the period; the backlog = open
  `planned` jobs with no schedule or no technician, most urgent first, at most 200; the skill
  catalogue and settings), `PUT /planning/jobs/{id}/schedule?dry_run&force`,
  `GET /planning/suggestions/{job_id}?from&to`, CRUD for `/planning/absences`, `/planning/skills`,
  `GET|PUT /planning/working-hours` (replaces the rows of one user or of the default),
  `GET|PUT /planning/users/{id}/skills`, `GET|PUT /planning/jobs/{id}/skills`,
  `GET|PUT /planning/settings`. Dates in queries and bodies accept a date or a date-time (the
  generated client sends the latter).
* **Scheduling** sets `scheduled_start/end` and replaces the technicians in one transaction,
  reusing the field module's `set_technicians`. Completed and cancelled jobs are refused with
  409 (also on a dry run). It writes an audit event (`job`/`scheduled`: times, technicians,
  conflict keys, whether it was forced). The result lists the conflicts either way.
* **Conflicts** (`conflicts::detect`, pure, unit-tested), per technician unless noted:
  `double_booked` (error; overlap with another planned or in-progress job of the technician
  including the buffer, names the other job; a job without an end counts as the default
  length), `on_absence` (error; any day of the job inside an absence), `outside_hours`
  (warning; some part of the job on some day is not covered by the union of that weekday's
  blocks, so lunch breaks and weekends count; a technician with no hours at all, own or default,
  is never "outside"), `missing_skill` (warning; one per missing required skill),
  `crosses_days` (warning, for the job, no technician; ending exactly at midnight does not
  cross). Each has a `message_key` (`planning.conflict.*`) that the client translates.
  **Errors refuse the change with 409 unless `force=true`; warnings never do.** `dry_run=true`
  changes nothing and sends no mail.
* **Suggestions** (`suggest::suggest`, pure, deterministic): for every technician and day in the
  range, the free gaps inside working hours (others' jobs padded with the buffer, absence days
  skipped; a technician with no hours is assumed to work Mon-Fri 08:00-17:00) that fit the job;
  one slot per gap at the first quarter hour. Ranking: fewest missing skills (technicians
  without the skills are included but last), earliest day, tightest fit (least unused time in
  the gap), earliest start, technician id. At most 10. The job's own duration is used, else the
  default length.
* **Mail.** Technicians newly assigned get an "assigned" mail and technicians who stay but whose
  appointment moved get a "rescheduled" mail, in their own `core.users.language` or the
  company default (five languages, same recipient lookup as ADR 0023), queued in the
  transaction. The planner who made the change is never mailed. Removed technicians are not
  told (yet).
* **Flutter** (`app/lib/features/planning/`): `ResourceBoard` is generic (rows, items, day
  columns, a time axis with 15-minute snapping, shading, drag targets) and knows nothing about
  jobs; `planning_adapter.dart` maps the API board to it. Blocks and backlog cards use
  `LongPressDraggable` (150 ms hold, so touch scrolling still works), no new dependency. While a
  drag hovers a cell the app calls the dry run (debounced) and shows a banner and a green/orange/red
  ghost; dropping with errors asks for confirmation and then sends `force=true`. Under 720 px
  wide the board becomes an agenda of the day (no dragging; a Plan dialog with technician chips,
  times, live conflicts and suggestions does the same job and is also on the wide layout).
  Administration (absences, working hours, skills, settings) is at `/planning/settings`.

**Consequences.**
* The board shows times in the **device's** time zone, while hours and absences are in the
  company zone: they only agree when the device is in the company's zone. Fine for one-country
  companies; a multi-zone company needs a time zone package in the app.
* The buffer is one number per company; a long drive and a short one are treated alike, and the
  first job of the day has no travel time from home.
* Double bookings are counted per technician; two people on one job see the conflict twice (once
  each). A job with several technicians appears as one block per technician.
* Suggestions look at gaps only; they do not move other jobs and offer one slot per gap, so a
  long gap is not offered at several start times.
* Absence rows are not an approval workflow; a planner enters them (technicians cannot request
  leave here).

**Not yet.** Work-centre capacity and finite loading (C3 second half, see
[ADR 0090](0090-work-centre-planning-board.md)), routing-based travel times and home addresses, mail when a
technician is removed from a job or on absence changes, recurring absences and public holidays,
resizing a block by its edge, a time-zone aware client.
