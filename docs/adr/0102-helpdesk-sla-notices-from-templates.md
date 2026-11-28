# 0102 — Helpdesk SLA notices from templates (A6b)

**Status:** Proposed (extends [ADR 0064](0064-helpdesk-sla-customer-notices.md) and
[ADR 0072](0072-helpdesk-reply-templates.md))

**Context.** SLA notices to the customer (ADR 0064) use built-in texts in five languages in
`sla_notice.rs`. An administrator cannot change the wording, add the company's tone or a phone number,
or offer a different text per team. Prepared answers (ADR 0072) already are the one template model, with
a `notice` kind, a team scope, one text per language and rendering that needs no logged-in user
(`ticket_values_for`, used by `send_email` automation). Two things are missing for notices: placeholders
for the deadline, and a way to say which answer a notice uses.

**Decision.**
- **New placeholders** (added to `render::PLACEHOLDERS`, filled by `ticket_values_for`, so they work in
  every prepared answer, not only notices):
  - `sla.target`: the first-response target as words in the answer's language (`2 uur`, `3 jours`),
    from `duration_text`.
  - `sla.due`: the deadline as a local date and time (`27/11/2026 14:30`), in the team's business
    calendar zone, else the default zone.
  - `sla.zone`: the zone name, so `{{sla.due}} ({{sla.zone}})` reads like the built-in text.
  - `sla.hours_note`: one sentence that the deadline counts in opening hours, in the answer's language,
    empty when the deadline is in calendar time.
  Empty values stay visible as `{{name}}`, as today, so an agent who uses a notice answer by hand sees
  what is missing. A notice with an unresolved placeholder falls back to the built-in text (below).
- **Per rule, optional answers.** `helpdesk.sla_notice_settings` gains `ack_answer_id` and
  `breach_answer_id` (nullable, `ON DELETE SET NULL`, company-checked). A rule without an answer keeps
  the built-in text, so nothing changes until an administrator picks one.
- **Validation on save** (same checks as `send_email` with `answer_id`, ADR 0072): the answer exists in
  the company, has kind `notice` and no team scope that excludes the rule's team, has a subject and a
  body in the company default language, and every `{{name}}` is a known placeholder.
- **Rendering.** `sla_notice::queue` loads the chosen answer and picks the text for the ticket's language
  with the usual fallback to the company default language. The subject keeps the `[Ticket#number]` tag:
  it is appended when the template subject does not contain it, so a customer's reply still lands on the
  ticket. Subjects are one line (`one_line`).
- **Fallback.** If the answer was deleted or archived, has no usable text, or a placeholder is still
  unresolved after rendering, the notice is sent with the built-in text and the reason is logged in
  `sla_notice_log.note`. A notice is never dropped because of a template problem: it exists to tell a
  customer they are not forgotten.
- **Unchanged.** Loop guards, the per-address hourly cap, "once per ticket" in `sla_notice_log`, the
  channel and internal/split/merged gates, and the outbox policy of the environment (ADR 0048).
- **API.** `SlaNoticeRule` gains `ack_answer_id` and `breach_answer_id`; `PUT /helpdesk/sla-notices`
  validates them. `GET /prepared-answers/placeholders` lists the new names. OpenAPI, Dart and Leptos
  clients are regenerated.
- **Screens.** Flutter and Leptos settings show an answer picker (kind `notice` only) per notice, with a
  preview rendered against a sample ticket.

**Consequences.** Wording becomes the company's own in all five languages without a code change. The
built-in texts stay as the default and the fallback, so existing installations behave the same. The new
placeholders also help agents in ordinary replies ("we will answer by {{sla.due}}").

**Deferred.** A preview with a real ticket, and templates for other system mail (CSAT survey, scheduled
report mails).
