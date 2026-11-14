# 0052 — Worker heartbeat and the "worker was down" alert

**Status:** Accepted

**Context.** `apps/worker` is one polling loop. It fetches helpdesk mail over IMAP, escalates SLA
breaches, generates maintenance-contract visits, recomputes product co-occurrence and sends both
e-mail outboxes. When it stops (a crash, a container that is not restarted, a deploy that forgot it,
a pass that hangs on a stuck mail server), nothing reports it: mail piles up in the outbox, SLA
breaches go unescalated, and nobody notices until a customer asks why they got no answer.
Roadmap item D1.

**Decision.** The worker writes a heartbeat; the API reports its age to administrators; the app
warns them while it is down; a mail goes to them when it comes back after a gap.

*Schema.* `core.worker_heartbeat` holds one row (`id boolean PRIMARY KEY CHECK (id)`): the time of
the last beat, when the beating process started, its polling interval, version and host. It is not
per company: one worker serves every company in the database. Several workers may run at once, so
the row says "at least one worker is alive", not which one; the last writer's details win.
`core.worker_outages (down_from, down_until)` records each gap.

*Beat.* At the start of every pass, before any work, `core::worker::beat` locks the row, reads the
previous beat and writes the new one, all by the database clock (`now()`). Beating first means a pass
that hangs stops the beat. A failed beat is logged and the pass continues.

*When the worker counts as down.* The last beat is older than three passes plus a minute of grace,
using the interval the beating worker reported: 150 seconds with the default `POLL_SECONDS=30`. The
grace covers a slow pass (a large outbox, a slow IMAP server); a quick restart stays under it.

*The alert.* When `beat` finds the previous beat late, it inserts the outage and queues one system
mail (`core.mail_outbox`) per active user with the `admin` role per company, in that company's name,
in the same transaction. The text names the period and what did not happen in it (mail, SLA
escalation, contract visits), in the user's language or else the company's. Times are written in
UTC, because the worker has no company and so no time zone. The row lock makes two workers that come
back together record and mail the gap once. Outside live environments the mail goes to files like
all other mail (ADR 0048).

The mail can only go out once the worker runs again, since the worker is what sends mail. That is
why the app also warns while the worker is down.

*API.* `GET /api/v1/admin/worker` (`users.admin`) returns `state` (`running`, `down` or
`never_seen`), the last beat and its age in seconds, the `late_after_seconds` threshold, the interval,
start time, version and host, and the most recent ended outage.

*App.* For users with `users.admin`, the shell asks every minute and shows an amber strip under the
environment banner when the state is `down` or `never_seen`. It says since when no worker has run and
that e-mail is not being sent. A user without the permission never calls the endpoint.

**Alternatives.**
- *A row per worker process.* It shows each worker, but needs pruning, and "down" becomes "none of
  them beat". One row answers the question that matters.
- *An external monitor (an uptime checker, a process supervisor).* Still useful, and the endpoint can
  feed one. But it is not part of every installation, and it would not tell the administrators in
  the app.
- *Alert from the API when it notices the gap.* The API cannot send mail either (the worker does),
  and an API that runs without traffic would not notice. The in-app warning covers "while down", and
  the mail covers "after the fact".

**Consequences.**
- A fresh installation without a worker shows administrators the warning until one runs. That is
  intended: without a worker no mail is sent.
- Changing `POLL_SECONDS` changes the threshold on the next beat.
- `envctl clone` empties both tables (`scrub_credentials.sql`). Otherwise the clone's first worker
  would report the time since the dump as an outage.
- Outages are kept; there are few, and they are a record for the backup and operations work (D2).
