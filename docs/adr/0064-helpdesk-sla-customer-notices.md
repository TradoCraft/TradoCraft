# 0064 — Helpdesk: SLA notices to the customer

**Status:** Accepted

**Context.** ADR 0017 and 0021 measure the first response and resolution times, in business time, and the
worker tells *staff* when a time has run out. The customer hears nothing: no confirmation that the request
arrived, no ticket number to quote and no word when the answer is late. Both notices must be switchable,
because some teams do not want automatic mail, and they must not fire out of hours or in a test
environment.

**Decision.**

* **Settings.** `helpdesk.sla_notice_settings (company_id, team_id?, priority?, ack_enabled,
  breach_enabled)`, unique per company, team and priority (`NULLS NOT DISTINCT`: a null team or priority
  means "all"). The rule that applies to a ticket is the most specific one: team and priority, then team,
  then priority, then neither (`sla_notice::pick`, unit tested). **No rule means no notice**, so nothing
  changes for existing installations. `GET/PUT /helpdesk/sla-notices` (`helpdesk.admin`) read and
  replace the complete list in one transaction; teams must belong to the company (404), duplicates and
  unknown priorities are 422; the change is audited (`sla_notices_updated`). Flutter: a card on the
  helpdesk settings page (team, priority, *Acknowledgement* and *Late notice* switches per rule).
* **Acknowledgement.** Sent when a ticket is created, from the end of `automation::run` for the `created`
  trigger, which every creation path already calls, so it sees the priority and team that the automation
  rules and the default team left, and the SLA times `sla::sync` computed. It contains the ticket number
  (and the `[Ticket#number]` tag in the subject, so replies thread into the ticket), the subject, the
  target response time as a duration ("4 hours", "3 days") and, as a deadline, the due moment in the zone
  of the business calendar (default `Europe/Brussels` without one). With a calendar the mail says the
  time counts in opening hours. It is queued in the creation transaction and sent right away, also outside
  opening hours: the deadline in it is already in business time.
* **Breach notice.** `sla_notice::send_breach_notices`, a worker pass after `sla::escalate`: open tickets
  whose first response is overdue and not yet given, not paused for the customer. It is sent **only while the
  business is open** (`Calendar::is_open_at` for the ticket's team calendar; without a calendar always);
  outside the hours it waits for the next pass. Only the first response is reported to the customer, not
  the resolution time. Turning the rule on later notifies open tickets that are already late, once.
* **Which tickets.** Customer-initiated channels only (`email`, `portal`): not tickets made by staff
  (phone, manual), not internal, merged or split tickets (a split continues a conversation that already has
  a ticket). The contact address must be valid; addresses such as `noreply@`, `no-reply@`,
  `donotreply@`, `mailer-daemon@` and `postmaster@` are skipped, and at most five notices go to one
  address per hour, so two auto-responders cannot start a loop.
* **Once per ticket and kind**: `helpdesk.sla_notice_log (ticket_id, kind, address, sent_at)` with the
  primary key as the claim (`INSERT .. ON CONFLICT DO NOTHING`), so concurrent workers or a repeated pass
  send once. Audited as system events `sla_ack_sent` and `sla_breach_notice_sent` (no address in the data).
* **Language.** The ticket's language, which was set at creation from the contact's own language, else the
  customer's, else the language detected in the mail, else the company default (ADR 0013, 0014), so a
  customer without a preference gets the company's language. Texts are fixed, in the five languages, in
  `sla_notice.rs`; they are replaced by templates with A6.
* **Environments.** The mail goes through `core.mail_outbox`; outside a live environment the worker writes
  files instead of sending (ADR 0048).

**Consequences.**
* A ticket created before a rule was switched on is never acknowledged afterwards.
* The breach notice depends on the worker running; with several calendars the first open instant per team
  decides, checked once per pass (30 seconds by default).
* `first_response_due_at` is recomputed when the calendar changes; a ticket that was late may stop being late
  and then gets no notice.
* The language of a notice follows the ticket, so editing the ticket language changes later notices only.

**Not yet.** Editable texts and per-team wording (A6), a resolution notice, notices for tickets made by staff
and a log of sent notices in the ticket screen (the audit trail has them).
